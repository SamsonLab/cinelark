use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::Sha256;
use subtle::ConstantTimeEq;
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
use uuid::Uuid;

use crate::remote_identity::IdentityMaterial;

pub const PROTOCOL_VERSION: u8 = 1;
pub const MAX_MESSAGE_BYTES: usize = 65_536;
pub const DEVICE_SECRET_BYTES: usize = 32;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteEnvelope {
    pub protocol_version: u8,
    pub id: String,
    #[serde(rename = "type")]
    pub message_type: String,
    pub sent_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reply_to: Option<String>,
    pub sequence: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revision: Option<u64>,
    pub payload: Value,
}

impl RemoteEnvelope {
    pub fn server_message(
        message_type: impl Into<String>,
        sequence: u64,
        reply_to: Option<String>,
        revision: Option<u64>,
        payload: Value,
    ) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            id: Uuid::new_v4().to_string(),
            message_type: message_type.into(),
            sent_at: OffsetDateTime::now_utc()
                .format(&Rfc3339)
                .expect("system time formats as RFC 3339"),
            reply_to,
            sequence,
            revision,
            payload,
        }
    }

    pub fn validate(&self) -> bool {
        self.protocol_version == PROTOCOL_VERSION
            && Uuid::parse_str(&self.id).is_ok()
            && self.message_type.contains('.')
            && self.payload.is_object()
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceConfiguration {
    #[serde(rename = "deviceID")]
    pub device_id: String,
    pub credential: String,
    #[serde(default)]
    pub capabilities: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum ParentInput {
    Configure {
        #[serde(rename = "serviceID")]
        service_id: String,
        name: String,
        #[serde(rename = "portStart", default = "default_port_start")]
        port_start: u16,
        #[serde(rename = "portEnd", default = "default_port_end")]
        port_end: u16,
        identity: Option<IdentityMaterial>,
        #[serde(default)]
        devices: Vec<DeviceConfiguration>,
    },
    StartPairing {
        secret: String,
        #[serde(rename = "expiresAtUnixMilliseconds")]
        expires_at_unix_milliseconds: i64,
    },
    StopPairing,
    ApprovePairing {
        #[serde(rename = "connectionID")]
        connection_id: String,
        #[serde(rename = "deviceID")]
        device_id: String,
        credential: String,
        #[serde(default)]
        capabilities: Vec<String>,
    },
    RejectPairing {
        #[serde(rename = "connectionID")]
        connection_id: String,
        code: String,
    },
    Send {
        #[serde(rename = "connectionID")]
        connection_id: String,
        #[serde(rename = "type")]
        message_type: String,
        #[serde(rename = "replyTo")]
        reply_to: Option<String>,
        revision: Option<u64>,
        payload: Value,
    },
    Broadcast {
        #[serde(rename = "type")]
        message_type: String,
        revision: Option<u64>,
        payload: Value,
    },
    RevokeDevice {
        #[serde(rename = "deviceID")]
        device_id: String,
    },
    Shutdown,
}

#[derive(Clone, Debug, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum ParentOutput {
    IdentityGenerated {
        identity: IdentityMaterial,
        fingerprint: String,
    },
    Ready {
        #[serde(rename = "protocolVersion")]
        protocol_version: u8,
        port: u16,
        fingerprint: String,
    },
    PairingRequested {
        #[serde(rename = "connectionID")]
        connection_id: String,
        #[serde(rename = "deviceID")]
        device_id: String,
        #[serde(rename = "deviceName")]
        device_name: String,
    },
    Connected {
        #[serde(rename = "connectionID")]
        connection_id: String,
        #[serde(rename = "deviceID")]
        device_id: String,
    },
    Envelope {
        #[serde(rename = "connectionID")]
        connection_id: String,
        #[serde(rename = "deviceID")]
        device_id: String,
        envelope: RemoteEnvelope,
    },
    Disconnected {
        #[serde(rename = "connectionID")]
        connection_id: String,
        #[serde(rename = "deviceID", skip_serializing_if = "Option::is_none")]
        device_id: Option<String>,
        reason: String,
    },
    Error {
        code: &'static str,
        message: &'static str,
    },
}

pub fn decode_secret(value: &str) -> Option<Vec<u8>> {
    let decoded = URL_SAFE_NO_PAD.decode(value).ok()?;
    (decoded.len() == DEVICE_SECRET_BYTES).then_some(decoded)
}

pub fn secrets_equal(left: &[u8], right: &[u8]) -> bool {
    left.len() == right.len() && left.ct_eq(right).into()
}

pub fn authentication_input(service_id: &str, connection_id: &str, nonce: &str) -> Vec<u8> {
    format!("{service_id}\n{connection_id}\n{nonce}").into_bytes()
}

#[cfg(test)]
pub fn authentication_code(secret: &[u8], input: &[u8]) -> String {
    let mut mac = Hmac::<Sha256>::new_from_slice(secret).expect("HMAC accepts arbitrary key sizes");
    mac.update(input);
    URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes())
}

pub fn verify_authentication_code(secret: &[u8], input: &[u8], provided: &str) -> bool {
    let Ok(provided) = URL_SAFE_NO_PAD.decode(provided) else {
        return false;
    };
    let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(secret) else {
        return false;
    };
    mac.update(input);
    mac.verify_slice(&provided).is_ok()
}

const fn default_port_start() -> u16 {
    43_201
}

const fn default_port_end() -> u16 {
    43_210
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn authentication_proof_is_bound_to_the_connection() {
        let credential = [7_u8; DEVICE_SECRET_BYTES];
        let first = authentication_input("service", "connection-a", "nonce");
        let second = authentication_input("service", "connection-b", "nonce");
        let proof = authentication_code(&credential, &first);
        assert!(verify_authentication_code(&credential, &first, &proof));
        assert!(!verify_authentication_code(&credential, &second, &proof));
    }

    #[test]
    fn authentication_matches_the_shared_cross_runtime_vector() {
        let vector: Value = serde_json::from_str(include_str!(
            "../../../../fixtures/conformance/remote-authentication-vector.json"
        ))
        .unwrap();
        let credential = decode_secret(vector["credentialBase64URL"].as_str().unwrap()).unwrap();
        let input = authentication_input(
            vector["serviceID"].as_str().unwrap(),
            vector["connectionID"].as_str().unwrap(),
            vector["nonce"].as_str().unwrap(),
        );
        assert_eq!(
            authentication_code(&credential, &input),
            vector["proofBase64URL"].as_str().unwrap()
        );
    }

    #[test]
    fn envelope_validation_rejects_protocol_and_identifier_drift() {
        let mut envelope =
            RemoteEnvelope::server_message("session.ready", 0, None, None, json!({}));
        assert!(envelope.validate());
        envelope.protocol_version = 2;
        assert!(!envelope.validate());
        envelope.protocol_version = 1;
        envelope.id = "not-a-uuid".to_owned();
        assert!(!envelope.validate());
    }

    #[test]
    fn secrets_require_256_bits_and_compare_without_early_exit() {
        let encoded = URL_SAFE_NO_PAD.encode([9_u8; DEVICE_SECRET_BYTES]);
        assert_eq!(
            decode_secret(&encoded),
            Some(vec![9_u8; DEVICE_SECRET_BYTES])
        );
        assert_eq!(decode_secret("short"), None);
        assert!(secrets_equal(&[1_u8; 32], &[1_u8; 32]));
        assert!(!secrets_equal(&[1_u8; 32], &[2_u8; 32]));
    }

    #[test]
    fn start_pairing_frame_decodes_json_milliseconds() {
        let frame = serde_json::from_value::<ParentInput>(json!({
            "kind": "startPairing",
            "secret": URL_SAFE_NO_PAD.encode([5_u8; DEVICE_SECRET_BYTES]),
            "expiresAtUnixMilliseconds": 1_787_634_800_000_i64,
        }))
        .unwrap();

        assert!(matches!(
            frame,
            ParentInput::StartPairing {
                expires_at_unix_milliseconds: 1_787_634_800_000,
                ..
            }
        ));
    }

    #[test]
    fn configure_frame_accepts_swift_device_id_casing() {
        let frame = serde_json::from_value::<ParentInput>(json!({
            "kind": "configure",
            "serviceID": "ad54e7ba-9409-4f54-8c7c-65e781978cf9",
            "name": "CineLark",
            "portStart": 43_201,
            "portEnd": 43_210,
            "identity": null,
            "devices": [{
                "deviceID": "8dc63877-bf80-4d63-afc0-bec50d1ecb60",
                "credential": URL_SAFE_NO_PAD.encode([7_u8; DEVICE_SECRET_BYTES]),
                "capabilities": ["navigation.basic"],
            }],
        }))
        .unwrap();

        let ParentInput::Configure { devices, .. } = frame else {
            panic!("expected configure frame");
        };
        assert_eq!(devices[0].device_id, "8dc63877-bf80-4d63-afc0-bec50d1ecb60");
    }
}
