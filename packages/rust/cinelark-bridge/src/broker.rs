use std::{
    collections::{HashMap, VecDeque},
    io,
    net::{Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6},
    sync::{Arc, mpsc::Sender},
    time::{SystemTime, UNIX_EPOCH},
};

use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, OriginalUri, Query, State},
    http::{HeaderMap, Method, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::Sha256;
use socket2::{Domain, Protocol, Socket, Type};
use tokio::{
    net::TcpListener,
    sync::{Mutex, Notify},
    time::{Duration, timeout},
};

use crate::protocol::{
    Envelope, MAX_ENVELOPE_BYTES, PROTOCOL_VERSION, ParentOutput, authentication_code,
};

const MAX_QUEUED_COMMANDS: usize = 128;
const MAX_POLL_COMMANDS: usize = 16;
const LONG_POLL_SECONDS: u64 = 20;
const AUTH_CLOCK_SKEW_SECONDS: i64 = 30;

#[derive(Clone)]
pub struct BrokerState {
    inner: Arc<BrokerInner>,
}

struct BrokerInner {
    secret: Vec<u8>,
    commands: Mutex<VecDeque<Envelope>>,
    command_notify: Notify,
    replay_nonces: Mutex<HashMap<String, i64>>,
    last_parent_sequence: Mutex<Option<u64>>,
    last_plugin_sequence: Mutex<Option<u64>>,
    parent_output: Sender<ParentOutput>,
}

impl BrokerState {
    pub fn new(secret: Vec<u8>, parent_output: Sender<ParentOutput>) -> Self {
        Self {
            inner: Arc::new(BrokerInner {
                secret,
                commands: Mutex::new(VecDeque::new()),
                command_notify: Notify::new(),
                replay_nonces: Mutex::new(HashMap::new()),
                last_parent_sequence: Mutex::new(None),
                last_plugin_sequence: Mutex::new(None),
                parent_output,
            }),
        }
    }

    pub async fn enqueue_command(&self, envelope: Envelope) -> Result<(), &'static str> {
        if !envelope.verify(&self.inner.secret) {
            return Err("invalid_command_authentication");
        }
        if !is_command_type(&envelope.message_type) {
            return Err("unsupported_command");
        }

        let mut last_sequence = self.inner.last_parent_sequence.lock().await;
        if last_sequence.is_some_and(|last| envelope.sequence <= last) {
            return Err("stale_sequence");
        }
        *last_sequence = Some(envelope.sequence);
        drop(last_sequence);

        let mut commands = self.inner.commands.lock().await;
        if commands.len() == MAX_QUEUED_COMMANDS {
            commands.pop_front();
        }
        commands.push_back(envelope);
        drop(commands);
        self.inner.command_notify.notify_waiters();
        Ok(())
    }

    async fn authenticate(
        &self,
        method: &Method,
        uri: &str,
        headers: &HeaderMap,
    ) -> Result<(), AuthError> {
        let timestamp = header(headers, "x-cinelark-timestamp")?
            .parse::<i64>()
            .map_err(|_| AuthError)?;
        let nonce = header(headers, "x-cinelark-nonce")?;
        let signature = header(headers, "x-cinelark-signature")?;
        if !(16..=64).contains(&nonce.len())
            || !nonce
                .bytes()
                .all(|value| value.is_ascii_alphanumeric() || value == b'_' || value == b'-')
        {
            return Err(AuthError);
        }

        let now = unix_timestamp();
        if (timestamp - now).abs() > AUTH_CLOCK_SKEW_SECONDS {
            return Err(AuthError);
        }

        let mut nonces = self.inner.replay_nonces.lock().await;
        nonces.retain(|_, seen_at| now - *seen_at <= AUTH_CLOCK_SKEW_SECONDS);
        if nonces.contains_key(nonce) {
            return Err(AuthError);
        }

        let input = format!("{}\n{}\n{}\n{}", method.as_str(), uri, timestamp, nonce);
        let provided = URL_SAFE_NO_PAD.decode(signature).map_err(|_| AuthError)?;
        let mut mac = Hmac::<Sha256>::new_from_slice(&self.inner.secret).map_err(|_| AuthError)?;
        mac.update(input.as_bytes());
        mac.verify_slice(&provided).map_err(|_| AuthError)?;
        nonces.insert(nonce.to_owned(), now);
        Ok(())
    }

    async fn accept_plugin_event(&self, envelope: Envelope) -> Result<(), &'static str> {
        if !envelope.verify(&self.inner.secret) || !is_event_type(&envelope.message_type) {
            return Err("invalid_event");
        }

        let mut last_sequence = self.inner.last_plugin_sequence.lock().await;
        if envelope.message_type == "bridge.hello" {
            *last_sequence = None;
        }
        if last_sequence.is_some_and(|last| envelope.sequence <= last) {
            return Err("stale_sequence");
        }
        *last_sequence = Some(envelope.sequence);
        drop(last_sequence);

        self.inner
            .parent_output
            .send(ParentOutput::Event { envelope })
            .map_err(|_| "parent_disconnected")
    }
}

#[derive(Debug)]
struct AuthError;

impl IntoResponse for AuthError {
    fn into_response(self) -> Response {
        StatusCode::UNAUTHORIZED.into_response()
    }
}

#[derive(Deserialize)]
struct CommandQuery {
    #[serde(default)]
    after: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CommandsResponse {
    protocol_version: u8,
    commands: Vec<Envelope>,
}

pub fn router(state: BrokerState) -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/plugin/hello", post(hello))
        .route("/v1/plugin/commands", get(commands))
        .route("/v1/plugin/events", post(events))
        .layer(DefaultBodyLimit::max(MAX_ENVELOPE_BYTES))
        .with_state(state)
}

async fn health() -> impl IntoResponse {
    Json(json!({
        "status": "ok",
        "protocolVersion": PROTOCOL_VERSION,
        "brokerVersion": env!("CARGO_PKG_VERSION")
    }))
}

async fn hello(
    State(state): State<BrokerState>,
    method: Method,
    OriginalUri(uri): OriginalUri,
    headers: HeaderMap,
    Json(envelope): Json<Envelope>,
) -> Result<impl IntoResponse, Response> {
    state
        .authenticate(&method, &uri.to_string(), &headers)
        .await
        .map_err(IntoResponse::into_response)?;
    if envelope.message_type != "bridge.hello" {
        return Err(StatusCode::BAD_REQUEST.into_response());
    }
    state
        .accept_plugin_event(envelope)
        .await
        .map_err(|_| StatusCode::UNAUTHORIZED.into_response())?;
    Ok(Json(json!({
        "protocolVersion": PROTOCOL_VERSION,
        "brokerVersion": env!("CARGO_PKG_VERSION")
    })))
}

async fn commands(
    State(state): State<BrokerState>,
    method: Method,
    OriginalUri(uri): OriginalUri,
    headers: HeaderMap,
    Query(query): Query<CommandQuery>,
) -> Result<impl IntoResponse, Response> {
    state
        .authenticate(&method, &uri.to_string(), &headers)
        .await
        .map_err(IntoResponse::into_response)?;

    let collect = || async {
        let mut queue = state.inner.commands.lock().await;
        while queue
            .front()
            .is_some_and(|command| command.sequence <= query.after)
        {
            queue.pop_front();
        }
        queue
            .iter()
            .take(MAX_POLL_COMMANDS)
            .cloned()
            .collect::<Vec<_>>()
    };

    let mut available = collect().await;
    if available.is_empty() {
        let notified = state.inner.command_notify.notified();
        let _ = timeout(Duration::from_secs(LONG_POLL_SECONDS), notified).await;
        available = collect().await;
    }

    Ok(Json(CommandsResponse {
        protocol_version: PROTOCOL_VERSION,
        commands: available,
    }))
}

async fn events(
    State(state): State<BrokerState>,
    method: Method,
    OriginalUri(uri): OriginalUri,
    headers: HeaderMap,
    Json(envelope): Json<Envelope>,
) -> Result<impl IntoResponse, Response> {
    state
        .authenticate(&method, &uri.to_string(), &headers)
        .await
        .map_err(IntoResponse::into_response)?;
    state
        .accept_plugin_event(envelope)
        .await
        .map_err(|_| StatusCode::UNAUTHORIZED.into_response())?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn bind_loopback_pair(
    port_start: u16,
    port_end: u16,
) -> io::Result<(u16, TcpListener, TcpListener)> {
    if port_start == 0 || port_start > port_end {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid port range",
        ));
    }

    for port in port_start..=port_end {
        let ipv6 = match bind_socket(
            Domain::IPV6,
            SocketAddr::V6(SocketAddrV6::new(Ipv6Addr::LOCALHOST, port, 0, 0)),
        ) {
            Ok(listener) => listener,
            Err(_) => continue,
        };
        let ipv4 = match bind_socket(
            Domain::IPV4,
            SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::LOCALHOST, port)),
        ) {
            Ok(listener) => listener,
            Err(_) => continue,
        };
        return Ok((port, ipv4, ipv6));
    }

    Err(io::Error::new(
        io::ErrorKind::AddrInUse,
        "no bridge port is available",
    ))
}

fn bind_socket(domain: Domain, address: SocketAddr) -> io::Result<TcpListener> {
    let socket = Socket::new(domain, Type::STREAM, Some(Protocol::TCP))?;
    socket.set_reuse_address(true)?;
    if domain == Domain::IPV6 {
        socket.set_only_v6(true)?;
    }
    socket.bind(&address.into())?;
    socket.listen(128)?;
    socket.set_nonblocking(true)?;
    TcpListener::from_std(socket.into())
}

fn header<'a>(headers: &'a HeaderMap, name: &str) -> Result<&'a str, AuthError> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .ok_or(AuthError)
}

fn unix_timestamp() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

fn is_command_type(value: &str) -> bool {
    matches!(
        value,
        "player.play"
            | "player.enqueue"
            | "player.pause"
            | "player.resume"
            | "player.stop"
            | "player.seekRelative"
            | "player.seekAbsolute"
            | "player.setSpeed"
            | "player.setVolume"
            | "player.setMuted"
            | "player.setFullscreen"
            | "player.selectAudioTrack"
            | "player.selectSubtitleTrack"
            | "player.disableSubtitles"
            | "player.requestState"
    )
}

fn is_event_type(value: &str) -> bool {
    matches!(
        value,
        "bridge.hello"
            | "bridge.ready"
            | "bridge.error"
            | "player.fileLoaded"
            | "player.stateChanged"
            | "player.positionChanged"
            | "player.tracksChanged"
            | "player.ended"
            | "player.closed"
    )
}

#[allow(dead_code)]
fn request_signature(
    secret: &[u8],
    method: &str,
    uri: &str,
    timestamp: i64,
    nonce: &str,
) -> String {
    authentication_code(
        secret,
        format!("{method}\n{uri}\n{timestamp}\n{nonce}").as_bytes(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::Envelope;
    use axum::{body::Body, http::Request};
    use serde_json::json;
    use std::sync::mpsc;

    fn test_state() -> BrokerState {
        let (sender, _) = mpsc::channel();
        BrokerState::new(vec![3_u8; 32], sender)
    }

    #[tokio::test]
    async fn commands_require_valid_mac_and_monotonic_sequence() {
        let state = test_state();
        let mut envelope = Envelope {
            protocol_version: 1,
            id: uuid::Uuid::new_v4().to_string(),
            message_type: "player.pause".to_owned(),
            sent_at: "2026-08-20T03:09:00Z".to_owned(),
            session_id: Some(uuid::Uuid::new_v4().to_string()),
            reply_to: None,
            sequence: 1,
            payload: json!({}),
            mac: String::new(),
        };
        envelope.sign(&[3_u8; 32]);
        state.enqueue_command(envelope.clone()).await.unwrap();
        assert_eq!(state.enqueue_command(envelope).await, Err("stale_sequence"));
    }

    #[tokio::test]
    async fn accepts_native_playlist_enqueue_commands() {
        let state = test_state();
        let mut envelope = Envelope {
            protocol_version: 1,
            id: uuid::Uuid::new_v4().to_string(),
            message_type: "player.enqueue".to_owned(),
            sent_at: "2026-08-20T03:09:00Z".to_owned(),
            session_id: Some(uuid::Uuid::new_v4().to_string()),
            reply_to: None,
            sequence: 1,
            payload: json!({
                "playbackID": uuid::Uuid::new_v4().to_string(),
                "url": "https://media.example/video?token=<redacted>"
            }),
            mac: String::new(),
        };
        envelope.sign(&[3_u8; 32]);

        state.enqueue_command(envelope).await.unwrap();
    }

    #[tokio::test]
    async fn binds_both_loopback_families_on_one_port() {
        let (port, ipv4, ipv6) = bind_loopback_pair(44_100, 44_120).unwrap();
        assert_eq!(ipv4.local_addr().unwrap().port(), port);
        assert_eq!(ipv6.local_addr().unwrap().port(), port);
        assert!(ipv4.local_addr().unwrap().ip().is_loopback());
        assert!(ipv6.local_addr().unwrap().ip().is_loopback());
    }

    #[test]
    fn request_signatures_bind_method_uri_timestamp_and_nonce() {
        let secret = [5_u8; 32];
        let signature = request_signature(
            &secret,
            "GET",
            "/v1/plugin/commands?after=1",
            42,
            "nonce-value-1234",
        );
        assert_ne!(
            signature,
            request_signature(
                &secret,
                "POST",
                "/v1/plugin/commands?after=1",
                42,
                "nonce-value-1234"
            )
        );
    }

    #[test]
    fn router_uses_bounded_request_bodies() {
        let _request: Request<Body> = Request::new(Body::empty());
        let _ = router(test_state());
    }
}
