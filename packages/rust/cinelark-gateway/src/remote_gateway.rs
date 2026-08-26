use std::{
    collections::HashMap,
    net::{SocketAddr, TcpListener},
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result, bail};
use axum::{
    Router,
    extract::{
        State, WebSocketUpgrade,
        ws::{CloseFrame, Message, WebSocket},
    },
    response::Response,
    routing::get,
};
use axum_server::{Handle, tls_rustls::RustlsConfig};
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio::sync::{Mutex, RwLock, mpsc};
use uuid::Uuid;

use crate::{
    remote_identity::GatewayIdentity,
    remote_protocol::{
        DeviceConfiguration, MAX_MESSAGE_BYTES, ParentOutput, RemoteEnvelope, authentication_input,
        decode_secret, secrets_equal, verify_authentication_code,
    },
};

const RATE_WINDOW: Duration = Duration::from_secs(2);
const RATE_LIMIT: u32 = 120;
const MAX_CONNECTIONS: usize = 16;
const OUTBOUND_QUEUE_MESSAGES: usize = 128;
const AUTHENTICATION_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Clone, Debug)]
struct DeviceRecord {
    credential: Vec<u8>,
    capabilities: Vec<String>,
}

#[derive(Clone, Debug)]
struct PairingWindow {
    secret: Vec<u8>,
    expires_at_unix_milliseconds: i64,
}

#[derive(Debug)]
struct RateWindow {
    started_at: Instant,
    messages: u32,
}

impl RateWindow {
    fn new() -> Self {
        Self {
            started_at: Instant::now(),
            messages: 0,
        }
    }

    fn permit(&mut self) -> bool {
        let now = Instant::now();
        if now.duration_since(self.started_at) >= RATE_WINDOW {
            self.started_at = now;
            self.messages = 0;
        }
        if self.messages >= RATE_LIMIT {
            return false;
        }
        self.messages += 1;
        true
    }
}

enum SocketCommand {
    Envelope(RemoteEnvelope),
    Close(&'static str),
}

struct ConnectionRecord {
    connection_id: String,
    nonce: String,
    outbound: mpsc::Sender<SocketCommand>,
    device_id: RwLock<Option<String>>,
    pairing_pending: AtomicBool,
    next_inbound_sequence: AtomicU64,
    next_outbound_sequence: AtomicU64,
    rate_window: Mutex<RateWindow>,
}

impl ConnectionRecord {
    fn send(
        &self,
        message_type: impl Into<String>,
        reply_to: Option<String>,
        revision: Option<u64>,
        payload: Value,
    ) {
        let sequence = self.next_outbound_sequence.fetch_add(1, Ordering::Relaxed);
        let envelope =
            RemoteEnvelope::server_message(message_type, sequence, reply_to, revision, payload);
        let _ = self.outbound.try_send(SocketCommand::Envelope(envelope));
    }

    fn close(&self, reason: &'static str) {
        let _ = self.outbound.try_send(SocketCommand::Close(reason));
    }
}

pub struct GatewayState {
    service_id: String,
    service_name: String,
    host_output: mpsc::UnboundedSender<ParentOutput>,
    devices: RwLock<HashMap<String, DeviceRecord>>,
    pairing: RwLock<Option<PairingWindow>>,
    connections: RwLock<HashMap<String, Arc<ConnectionRecord>>>,
}

impl GatewayState {
    pub fn new(
        service_id: String,
        service_name: String,
        devices: Vec<DeviceConfiguration>,
        host_output: mpsc::UnboundedSender<ParentOutput>,
    ) -> Result<Arc<Self>> {
        Uuid::parse_str(&service_id).context("service ID must be a UUID")?;
        let mut records = HashMap::new();
        for device in devices {
            Uuid::parse_str(&device.device_id).context("device ID must be a UUID")?;
            let credential = decode_secret(&device.credential)
                .context("device credential must contain 256 bits")?;
            records.insert(
                device.device_id,
                DeviceRecord {
                    credential,
                    capabilities: device.capabilities,
                },
            );
        }
        Ok(Arc::new(Self {
            service_id,
            service_name,
            host_output,
            devices: RwLock::new(records),
            pairing: RwLock::new(None),
            connections: RwLock::new(HashMap::new()),
        }))
    }

    pub async fn start_pairing(
        &self,
        secret: String,
        expires_at_unix_milliseconds: i64,
    ) -> Result<()> {
        let secret = decode_secret(&secret).context("pairing secret must contain 256 bits")?;
        if expires_at_unix_milliseconds <= now_unix_milliseconds() {
            bail!("pairing window is already expired");
        }
        self.close_pending_pairings("pairingUnavailable").await;
        *self.pairing.write().await = Some(PairingWindow {
            secret,
            expires_at_unix_milliseconds,
        });
        eprintln!("[remote-gateway] pairing_window_opened");
        Ok(())
    }

    pub async fn stop_pairing(&self) {
        *self.pairing.write().await = None;
        self.close_pending_pairings("pairingUnavailable").await;
        eprintln!("[remote-gateway] pairing_window_closed");
    }

    pub async fn approve_pairing(
        &self,
        connection_id: &str,
        device_id: String,
        credential: String,
        capabilities: Vec<String>,
    ) -> Result<()> {
        Uuid::parse_str(&device_id).context("device ID must be a UUID")?;
        let decoded =
            decode_secret(&credential).context("device credential must contain 256 bits")?;
        let connection = self.connection(connection_id).await?;
        if !connection.pairing_pending.swap(false, Ordering::SeqCst) {
            bail!("connection has no pending pairing request");
        }
        self.devices.write().await.insert(
            device_id.clone(),
            DeviceRecord {
                credential: decoded,
                capabilities: capabilities.clone(),
            },
        );
        *connection.device_id.write().await = Some(device_id.clone());
        self.stop_pairing().await;
        connection.send(
            "pairing.approved",
            None,
            None,
            json!({
                "deviceID": device_id,
                "credential": credential,
                "capabilities": capabilities,
            }),
        );
        let _ = self.host_output.send(ParentOutput::Connected {
            connection_id: connection.connection_id.clone(),
            device_id,
        });
        Ok(())
    }

    pub async fn reject_pairing(&self, connection_id: &str, code: String) -> Result<()> {
        let connection = self.connection(connection_id).await?;
        connection.pairing_pending.store(false, Ordering::SeqCst);
        connection.send("pairing.rejected", None, None, json!({ "code": code }));
        connection.close("pairing_rejected");
        Ok(())
    }

    pub async fn send(
        &self,
        connection_id: &str,
        message_type: String,
        reply_to: Option<String>,
        revision: Option<u64>,
        payload: Value,
    ) -> Result<()> {
        let connection = self.connection(connection_id).await?;
        connection.send(message_type, reply_to, revision, payload);
        Ok(())
    }

    pub async fn broadcast(&self, message_type: String, revision: Option<u64>, payload: Value) {
        let connections = self
            .connections
            .read()
            .await
            .values()
            .cloned()
            .collect::<Vec<_>>();
        for connection in connections {
            if connection.device_id.read().await.is_some() {
                connection.send(message_type.clone(), None, revision, payload.clone());
            }
        }
    }

    pub async fn revoke_device(&self, device_id: &str) {
        self.devices.write().await.remove(device_id);
        let connections = self
            .connections
            .read()
            .await
            .values()
            .cloned()
            .collect::<Vec<_>>();
        for connection in connections {
            if connection.device_id.read().await.as_deref() == Some(device_id) {
                connection.send("session.revoked", None, None, json!({}));
                *connection.device_id.write().await = None;
                connection.close("revoked");
            }
        }
    }

    async fn connection(&self, connection_id: &str) -> Result<Arc<ConnectionRecord>> {
        self.connections
            .read()
            .await
            .get(connection_id)
            .cloned()
            .context("unknown Remote connection")
    }

    async fn close_pending_pairings(&self, code: &'static str) {
        let connections = self
            .connections
            .read()
            .await
            .values()
            .cloned()
            .collect::<Vec<_>>();
        for connection in connections {
            if connection.pairing_pending.swap(false, Ordering::SeqCst) {
                connection.send("pairing.rejected", None, None, json!({ "code": code }));
                connection.close("pairing_closed");
            }
        }
    }

    async fn handle_envelope(
        &self,
        connection: &Arc<ConnectionRecord>,
        envelope: RemoteEnvelope,
    ) -> Result<()> {
        if !envelope.validate() {
            bail!("invalidMessage");
        }
        let expected = connection.next_inbound_sequence.load(Ordering::Relaxed);
        if envelope.sequence != expected {
            bail!("staleSequence");
        }
        connection
            .next_inbound_sequence
            .store(expected + 1, Ordering::Relaxed);
        if !connection.rate_window.lock().await.permit() {
            bail!("rateLimited");
        }

        match envelope.message_type.as_str() {
            "pairing.request" => self.handle_pairing_request(connection, &envelope).await,
            "session.authenticate" => self.handle_authenticate(connection, &envelope).await,
            _ => {
                let Some(device_id) = connection.device_id.read().await.clone() else {
                    bail!("unauthenticated");
                };
                let _ = self.host_output.send(ParentOutput::Envelope {
                    connection_id: connection.connection_id.clone(),
                    device_id,
                    envelope,
                });
                Ok(())
            }
        }
    }

    async fn handle_pairing_request(
        &self,
        connection: &Arc<ConnectionRecord>,
        envelope: &RemoteEnvelope,
    ) -> Result<()> {
        eprintln!("[remote-gateway] pairing_request_received");
        if connection.device_id.read().await.is_some()
            || connection.pairing_pending.load(Ordering::Relaxed)
        {
            bail!("invalidState");
        }
        let provided = envelope
            .payload
            .get("secret")
            .and_then(Value::as_str)
            .and_then(decode_secret)
            .context("invalidMessage")?;
        let device_id = envelope
            .payload
            .get("deviceID")
            .and_then(Value::as_str)
            .context("invalidMessage")?;
        Uuid::parse_str(device_id).context("invalidMessage")?;
        let device_name = envelope
            .payload
            .get("deviceName")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty() && value.chars().count() <= 80)
            .context("invalidMessage")?;

        let mut pairing = self.pairing.write().await;
        let Some(window) = pairing.as_ref() else {
            eprintln!("[remote-gateway] pairing_request_rejected reason=no_window");
            bail!("pairingUnavailable");
        };
        if window.expires_at_unix_milliseconds <= now_unix_milliseconds() {
            eprintln!("[remote-gateway] pairing_request_rejected reason=expired");
            bail!("pairingUnavailable");
        }
        if !secrets_equal(&window.secret, &provided) {
            eprintln!("[remote-gateway] pairing_request_rejected reason=secret_mismatch");
            bail!("pairingUnavailable");
        }
        *pairing = None;
        connection.pairing_pending.store(true, Ordering::SeqCst);
        drop(pairing);
        connection.send(
            "pairing.pending",
            Some(envelope.id.clone()),
            None,
            json!({}),
        );
        let _ = self.host_output.send(ParentOutput::PairingRequested {
            connection_id: connection.connection_id.clone(),
            device_id: device_id.to_owned(),
            device_name: device_name.to_owned(),
        });
        eprintln!("[remote-gateway] pairing_pending_sent");
        Ok(())
    }

    async fn handle_authenticate(
        &self,
        connection: &Arc<ConnectionRecord>,
        envelope: &RemoteEnvelope,
    ) -> Result<()> {
        if connection.device_id.read().await.is_some() {
            bail!("invalidState");
        }
        let device_id = envelope
            .payload
            .get("deviceID")
            .and_then(Value::as_str)
            .context("invalidMessage")?;
        let proof = envelope
            .payload
            .get("proof")
            .and_then(Value::as_str)
            .context("invalidMessage")?;
        let devices = self.devices.read().await;
        let device = devices.get(device_id).context("unauthenticated")?;
        let input = authentication_input(
            &self.service_id,
            &connection.connection_id,
            &connection.nonce,
        );
        if !verify_authentication_code(&device.credential, &input, proof) {
            bail!("unauthenticated");
        }
        let capabilities = device.capabilities.clone();
        drop(devices);
        *connection.device_id.write().await = Some(device_id.to_owned());
        connection.send(
            "session.authenticated",
            Some(envelope.id.clone()),
            None,
            json!({ "capabilities": capabilities }),
        );
        let _ = self.host_output.send(ParentOutput::Connected {
            connection_id: connection.connection_id.clone(),
            device_id: device_id.to_owned(),
        });
        Ok(())
    }
}

pub async fn serve(
    listener: TcpListener,
    identity: GatewayIdentity,
    state: Arc<GatewayState>,
    handle: Handle<SocketAddr>,
) -> Result<()> {
    let tls = RustlsConfig::from_pem(
        identity.material.certificate_pem.into_bytes(),
        identity.material.private_key_pem.into_bytes(),
    )
    .await
    .context("configure Remote TLS")?;
    let app = Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/v1/remote", get(remote_upgrade))
        .with_state(state);
    axum_server::from_tcp_rustls(listener, tls)
        .context("create Remote TLS server")?
        .handle(handle)
        .serve(app.into_make_service())
        .await
        .context("serve Remote TLS")
}

async fn remote_upgrade(ws: WebSocketUpgrade, State(state): State<Arc<GatewayState>>) -> Response {
    eprintln!("[remote-gateway] websocket_upgrade_received");
    ws.max_message_size(MAX_MESSAGE_BYTES)
        .max_frame_size(MAX_MESSAGE_BYTES)
        .on_upgrade(move |socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: Arc<GatewayState>) {
    eprintln!("[remote-gateway] websocket_opened");
    let connection_id = Uuid::new_v4().to_string();
    let mut nonce_bytes = [0_u8; 32];
    if getrandom::fill(&mut nonce_bytes).is_err() {
        return;
    }
    let nonce = URL_SAFE_NO_PAD.encode(nonce_bytes);
    let (outbound, mut outbound_rx) = mpsc::channel(OUTBOUND_QUEUE_MESSAGES);
    let connection = Arc::new(ConnectionRecord {
        connection_id: connection_id.clone(),
        nonce: nonce.clone(),
        outbound,
        device_id: RwLock::new(None),
        pairing_pending: AtomicBool::new(false),
        next_inbound_sequence: AtomicU64::new(0),
        next_outbound_sequence: AtomicU64::new(0),
        rate_window: Mutex::new(RateWindow::new()),
    });
    {
        let mut connections = state.connections.write().await;
        if connections.len() >= MAX_CONNECTIONS {
            return;
        }
        connections.insert(connection_id.clone(), connection.clone());
    }
    connection.send(
        "session.challenge",
        None,
        None,
        json!({
            "connectionID": connection_id,
            "serviceID": state.service_id,
            "serviceName": state.service_name,
            "nonce": nonce,
            "protocolMin": 1,
            "protocolMax": 1,
        }),
    );
    eprintln!("[remote-gateway] session_challenge_sent");

    let (mut sink, mut stream) = socket.split();
    let writer = tokio::spawn(async move {
        while let Some(command) = outbound_rx.recv().await {
            match command {
                SocketCommand::Envelope(envelope) => {
                    let Ok(payload) = serde_json::to_string(&envelope) else {
                        break;
                    };
                    if sink.send(Message::Text(payload.into())).await.is_err() {
                        break;
                    }
                }
                SocketCommand::Close(reason) => {
                    let _ = sink
                        .send(Message::Close(Some(CloseFrame {
                            code: 1008,
                            reason: reason.into(),
                        })))
                        .await;
                    break;
                }
            }
        }
    });

    let mut disconnect_reason = "peer_closed".to_owned();
    loop {
        let next = if connection.device_id.read().await.is_none()
            && !connection.pairing_pending.load(Ordering::Relaxed)
        {
            match tokio::time::timeout(AUTHENTICATION_TIMEOUT, stream.next()).await {
                Ok(next) => next,
                Err(_) => {
                    disconnect_reason = "authentication_timeout".to_owned();
                    break;
                }
            }
        } else {
            stream.next().await
        };
        let Some(result) = next else { break };
        let message = match result {
            Ok(message) => message,
            Err(_) => {
                disconnect_reason = "transport_error".to_owned();
                break;
            }
        };
        match message {
            Message::Text(text) => {
                if text.len() > MAX_MESSAGE_BYTES {
                    disconnect_reason = "message_too_large".to_owned();
                    break;
                }
                let envelope = match serde_json::from_str::<RemoteEnvelope>(&text) {
                    Ok(envelope) => envelope,
                    Err(_) => {
                        disconnect_reason = "invalidMessage".to_owned();
                        break;
                    }
                };
                eprintln!(
                    "[remote-gateway] envelope_received type={} sequence={}",
                    envelope.message_type, envelope.sequence
                );
                if let Err(error) = state.handle_envelope(&connection, envelope).await {
                    let code = stable_error_code(&error);
                    eprintln!("[remote-gateway] envelope_rejected code={code}");
                    connection.send("session.error", None, None, json!({ "code": code }));
                    connection.close("policy_error");
                    disconnect_reason = "policy_error".to_owned();
                    break;
                }
            }
            Message::Ping(value) => {
                connection.send(
                    "session.pong",
                    None,
                    None,
                    json!({ "echo": URL_SAFE_NO_PAD.encode(value) }),
                );
            }
            Message::Close(_) => break,
            Message::Binary(_) | Message::Pong(_) => {}
        }
    }

    state
        .connections
        .write()
        .await
        .remove(&connection.connection_id);
    let device_id = connection.device_id.read().await.clone();
    let disconnected_connection_id = connection.connection_id.clone();
    drop(connection);
    let _ = writer.await;
    eprintln!("[remote-gateway] websocket_closed reason={disconnect_reason}");
    let _ = state.host_output.send(ParentOutput::Disconnected {
        connection_id: disconnected_connection_id,
        device_id,
        reason: disconnect_reason,
    });
}

fn stable_error_code(error: &anyhow::Error) -> &'static str {
    match error.to_string().as_str() {
        "invalidMessage" => "invalidMessage",
        "staleSequence" => "staleSequence",
        "rateLimited" => "rateLimited",
        "invalidState" => "invalidState",
        "pairingUnavailable" => "pairingUnavailable",
        "unauthenticated" => "unauthenticated",
        _ => "internal",
    }
}

pub fn bind_available(port_start: u16, port_end: u16) -> Result<(TcpListener, u16)> {
    if port_start == 0 || port_end < port_start {
        bail!("invalid Remote port range");
    }
    for port in port_start..=port_end {
        if let Ok(listener) = TcpListener::bind(("0.0.0.0", port)) {
            listener
                .set_nonblocking(true)
                .context("configure Remote listener")?;
            return Ok((listener, port));
        }
    }
    bail!("no Remote port is available")
}

fn now_unix_milliseconds() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::remote_protocol::authentication_code;
    use rustls::{ClientConfig, RootCertStore};
    use rustls_pki_types::CertificateDer;
    use tokio_tungstenite::{
        Connector, connect_async_tls_with_config, tungstenite::Message as ClientMessage,
    };

    fn configured_state() -> (
        Arc<GatewayState>,
        mpsc::UnboundedReceiver<ParentOutput>,
        String,
    ) {
        let (output, receiver) = mpsc::unbounded_channel();
        let credential = URL_SAFE_NO_PAD.encode([3_u8; 32]);
        let state = GatewayState::new(
            "ad54e7ba-9409-4f54-8c7c-65e781978cf9".to_owned(),
            "Living Room Mac".to_owned(),
            vec![DeviceConfiguration {
                device_id: "f581875b-a075-46e8-ae49-8deafc7d5242".to_owned(),
                credential,
                capabilities: vec!["navigation.basic".to_owned()],
            }],
            output,
        )
        .unwrap();
        (state, receiver, URL_SAFE_NO_PAD.encode([3_u8; 32]))
    }

    fn synthetic_connection() -> Arc<ConnectionRecord> {
        let (outbound, _) = mpsc::channel(OUTBOUND_QUEUE_MESSAGES);
        Arc::new(ConnectionRecord {
            connection_id: Uuid::new_v4().to_string(),
            nonce: URL_SAFE_NO_PAD.encode([8_u8; 32]),
            outbound,
            device_id: RwLock::new(None),
            pairing_pending: AtomicBool::new(false),
            next_inbound_sequence: AtomicU64::new(0),
            next_outbound_sequence: AtomicU64::new(0),
            rate_window: Mutex::new(RateWindow::new()),
        })
    }

    #[tokio::test]
    async fn pairing_window_requires_a_future_expiry() {
        let (state, _, _) = configured_state();
        let secret = URL_SAFE_NO_PAD.encode([5_u8; 32]);
        assert!(
            state
                .start_pairing(secret.clone(), now_unix_milliseconds() - 1)
                .await
                .is_err()
        );
        assert!(
            state
                .start_pairing(secret, now_unix_milliseconds() + 10_000)
                .await
                .is_ok()
        );
    }

    #[tokio::test]
    async fn pairing_secret_is_consumed_by_the_first_valid_request() {
        let (state, _, _) = configured_state();
        let secret = URL_SAFE_NO_PAD.encode([5_u8; 32]);
        state
            .start_pairing(secret.clone(), now_unix_milliseconds() + 10_000)
            .await
            .unwrap();
        let request = RemoteEnvelope::server_message(
            "pairing.request",
            0,
            None,
            None,
            json!({
                "secret": secret,
                "deviceID": Uuid::new_v4().to_string(),
                "deviceName": "Synthetic Phone",
            }),
        );

        state
            .handle_pairing_request(&synthetic_connection(), &request)
            .await
            .unwrap();

        assert!(state.pairing.read().await.is_none());
        let second = state
            .handle_pairing_request(&synthetic_connection(), &request)
            .await
            .unwrap_err();
        assert_eq!(second.to_string(), "pairingUnavailable");
    }

    #[test]
    fn port_selection_rejects_invalid_ranges() {
        assert!(bind_available(0, 0).is_err());
        assert!(bind_available(9, 8).is_err());
    }

    #[test]
    fn authentication_fixture_can_be_derived_without_transport_state() {
        let (_, _, credential) = configured_state();
        let decoded = decode_secret(&credential).unwrap();
        let input = authentication_input(
            "ad54e7ba-9409-4f54-8c7c-65e781978cf9",
            "8dc63877-bf80-4d63-afc0-bec50d1ecb60",
            "synthetic-nonce",
        );
        let proof = authentication_code(&decoded, &input);
        assert!(verify_authentication_code(&decoded, &input, &proof));
    }

    #[test]
    fn wire_errors_are_restricted_to_stable_codes() {
        assert_eq!(
            stable_error_code(&anyhow::anyhow!("staleSequence")),
            "staleSequence"
        );
        assert_eq!(
            stable_error_code(&anyhow::anyhow!("database details")),
            "internal"
        );
    }

    #[tokio::test]
    async fn pinned_wss_pairing_forwards_only_after_authentication() {
        let (host_output, mut host_output_rx) = mpsc::unbounded_channel();
        let service_id = "ad54e7ba-9409-4f54-8c7c-65e781978cf9".to_owned();
        let state = GatewayState::new(
            service_id.clone(),
            "Living Room Mac".to_owned(),
            vec![],
            host_output,
        )
        .unwrap();
        let pairing_secret = URL_SAFE_NO_PAD.encode([5_u8; 32]);
        state
            .start_pairing(pairing_secret.clone(), now_unix_milliseconds() + 30_000)
            .await
            .unwrap();

        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        listener.set_nonblocking(true).unwrap();
        let port = listener.local_addr().unwrap().port();
        let identity = GatewayIdentity::generate().unwrap();
        let mut roots = RootCertStore::empty();
        roots
            .add(CertificateDer::from(identity.certificate_der().unwrap()))
            .unwrap();
        let client_config = ClientConfig::builder_with_provider(
            rustls::crypto::aws_lc_rs::default_provider().into(),
        )
        .with_protocol_versions(&[&rustls::version::TLS12])
        .unwrap()
        .with_root_certificates(roots)
        .with_no_client_auth();
        let handle = Handle::<SocketAddr>::new();
        let server = tokio::spawn(serve(
            listener,
            identity,
            Arc::clone(&state),
            handle.clone(),
        ));

        let (mut socket, _) = connect_async_tls_with_config(
            format!("wss://localhost:{port}/v1/remote"),
            None,
            false,
            Some(Connector::Rustls(Arc::new(client_config))),
        )
        .await
        .unwrap();
        let challenge = socket.next().await.unwrap().unwrap().into_text().unwrap();
        let challenge: RemoteEnvelope = serde_json::from_str(&challenge).unwrap();
        assert_eq!(challenge.message_type, "session.challenge");
        let connection_id = challenge.payload["connectionID"]
            .as_str()
            .unwrap()
            .to_owned();

        let pairing_request = RemoteEnvelope::server_message(
            "pairing.request",
            0,
            None,
            None,
            json!({
                "deviceID": "f581875b-a075-46e8-ae49-8deafc7d5242",
                "deviceName": "Synthetic Phone",
                "secret": pairing_secret,
            }),
        );
        socket
            .send(ClientMessage::Text(
                serde_json::to_string(&pairing_request).unwrap().into(),
            ))
            .await
            .unwrap();
        let pending = socket.next().await.unwrap().unwrap().into_text().unwrap();
        let pending: RemoteEnvelope = serde_json::from_str(&pending).unwrap();
        assert_eq!(pending.message_type, "pairing.pending");
        let requested = host_output_rx.recv().await.unwrap();
        assert!(matches!(
            requested,
            ParentOutput::PairingRequested { ref connection_id, .. }
                if connection_id == &challenge.payload["connectionID"]
        ));

        let credential = URL_SAFE_NO_PAD.encode([7_u8; 32]);
        state
            .approve_pairing(
                &connection_id,
                "f581875b-a075-46e8-ae49-8deafc7d5242".to_owned(),
                credential,
                vec!["navigation.basic".to_owned()],
            )
            .await
            .unwrap();
        let approved = socket.next().await.unwrap().unwrap().into_text().unwrap();
        let approved: RemoteEnvelope = serde_json::from_str(&approved).unwrap();
        assert_eq!(approved.message_type, "pairing.approved");
        assert!(matches!(
            host_output_rx.recv().await.unwrap(),
            ParentOutput::Connected { .. }
        ));

        let navigation = RemoteEnvelope::server_message(
            "navigation.move",
            1,
            None,
            None,
            json!({ "direction": "left" }),
        );
        socket
            .send(ClientMessage::Text(
                serde_json::to_string(&navigation).unwrap().into(),
            ))
            .await
            .unwrap();
        let forwarded = host_output_rx.recv().await.unwrap();
        assert!(matches!(
            forwarded,
            ParentOutput::Envelope { envelope, .. }
                if envelope.message_type == "navigation.move"
        ));

        let _ = socket.close(None).await;
        handle.shutdown();
        server.await.unwrap().unwrap();
    }
}
