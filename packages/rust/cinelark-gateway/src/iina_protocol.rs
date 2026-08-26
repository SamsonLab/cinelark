use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::Sha256;

pub const PROTOCOL_VERSION: u8 = 1;
pub const MAX_ENVELOPE_BYTES: usize = 262_144;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Envelope {
    pub protocol_version: u8,
    pub id: String,
    #[serde(rename = "type")]
    pub message_type: String,
    pub sent_at: String,
    #[serde(rename = "sessionID", skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reply_to: Option<String>,
    pub sequence: u64,
    pub payload: Value,
    pub mac: String,
}

impl Envelope {
    pub fn signing_input(&self) -> Vec<u8> {
        format!(
            "{}\n{}\n{}\n{}\n{}\n{}\n{}\n{}",
            self.protocol_version,
            self.id,
            self.message_type,
            self.sent_at,
            self.session_id.as_deref().unwrap_or_default(),
            self.reply_to.as_deref().unwrap_or_default(),
            self.sequence,
            canonical_json(&self.payload),
        )
        .into_bytes()
    }

    #[cfg(test)]
    pub fn sign(&mut self, secret: &[u8]) {
        self.mac = authentication_code(secret, &self.signing_input());
    }

    pub fn verify(&self, secret: &[u8]) -> bool {
        if self.protocol_version != PROTOCOL_VERSION {
            return false;
        }
        let Ok(provided) = URL_SAFE_NO_PAD.decode(&self.mac) else {
            return false;
        };
        let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(secret) else {
            return false;
        };
        mac.update(&self.signing_input());
        mac.verify_slice(&provided).is_ok()
    }
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum ParentInput {
    Configure {
        secret: String,
        #[serde(rename = "portStart", default = "default_port_start")]
        port_start: u16,
        #[serde(rename = "portEnd", default = "default_port_end")]
        port_end: u16,
    },
    Command {
        envelope: Envelope,
    },
    Shutdown,
}

#[derive(Clone, Debug, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum ParentOutput {
    Ready {
        #[serde(rename = "protocolVersion")]
        protocol_version: u8,
        port: u16,
    },
    Event {
        envelope: Envelope,
    },
    Error {
        code: &'static str,
        message: &'static str,
    },
}

pub fn decode_secret(value: &str) -> Option<Vec<u8>> {
    let decoded = URL_SAFE_NO_PAD.decode(value).ok()?;
    (decoded.len() == 32).then_some(decoded)
}

pub fn authentication_code(secret: &[u8], input: &[u8]) -> String {
    let mut mac = Hmac::<Sha256>::new_from_slice(secret).expect("HMAC accepts arbitrary key sizes");
    mac.update(input);
    URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes())
}

pub fn canonical_json(value: &Value) -> String {
    match value {
        Value::Null => "null".to_owned(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::String(value) => serde_json::to_string(value).expect("strings serialize"),
        Value::Array(values) => format!(
            "[{}]",
            values
                .iter()
                .map(canonical_json)
                .collect::<Vec<_>>()
                .join(",")
        ),
        Value::Object(values) => {
            let mut keys = values.keys().collect::<Vec<_>>();
            keys.sort_unstable();
            let members = keys
                .into_iter()
                .map(|key| {
                    format!(
                        "{}:{}",
                        serde_json::to_string(key).expect("keys serialize"),
                        canonical_json(&values[key])
                    )
                })
                .collect::<Vec<_>>()
                .join(",");
            format!("{{{members}}}")
        }
    }
}

const fn default_port_start() -> u16 {
    43_191
}

const fn default_port_end() -> u16 {
    43_200
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn envelope() -> Envelope {
        Envelope {
            protocol_version: 1,
            id: "4ff6c27e-1415-473f-8764-451d6a3369cb".to_owned(),
            message_type: "player.requestState".to_owned(),
            sent_at: "2026-08-20T03:09:00Z".to_owned(),
            session_id: Some("6f55936d-5950-44fd-a696-f989d41785cc".to_owned()),
            reply_to: None,
            sequence: 42,
            payload: json!({"z": [2, 1], "a": true}),
            mac: String::new(),
        }
    }

    #[test]
    fn canonical_json_sorts_object_keys_recursively() {
        assert_eq!(
            canonical_json(&json!({"z": {"b": 2, "a": 1}, "a": true})),
            r#"{"a":true,"z":{"a":1,"b":2}}"#
        );
    }

    #[test]
    fn envelope_mac_detects_payload_changes() {
        let secret = [7_u8; 32];
        let mut value = envelope();
        value.sign(&secret);
        assert!(value.verify(&secret));
        value.payload = json!({"a": false});
        assert!(!value.verify(&secret));
    }

    #[test]
    fn authentication_matches_the_shared_cross_runtime_vector() {
        let vector: Value = serde_json::from_str(include_str!(
            "../../../../fixtures/conformance/bridge-authentication-vector.json"
        ))
        .unwrap();
        let envelope: Envelope = serde_json::from_value(vector["envelope"].clone()).unwrap();
        let secret = decode_secret(vector["secretBase64URL"].as_str().unwrap()).unwrap();
        assert!(envelope.verify(&secret));
    }

    #[test]
    fn pairing_secret_must_be_256_bits() {
        let valid = URL_SAFE_NO_PAD.encode([9_u8; 32]);
        assert_eq!(decode_secret(&valid), Some(vec![9_u8; 32]));
        assert_eq!(decode_secret("short"), None);
    }
}
