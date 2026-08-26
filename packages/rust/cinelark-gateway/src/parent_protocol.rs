use serde::{Deserialize, Serialize};

use crate::{iina_protocol, remote_protocol};

#[derive(Debug, Deserialize)]
#[serde(tag = "center", content = "payload", rename_all = "camelCase")]
pub enum ParentInput {
    Iina(iina_protocol::ParentInput),
    Remote(remote_protocol::ParentInput),
    Process(ProcessInput),
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum ProcessInput {
    Shutdown,
}

#[derive(Clone, Debug, Serialize)]
#[serde(tag = "center", content = "payload", rename_all = "camelCase")]
pub enum ParentOutput {
    Iina(iina_protocol::ParentOutput),
    Remote(remote_protocol::ParentOutput),
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn input_routes_to_an_explicit_center() {
        let input = serde_json::from_value::<ParentInput>(json!({
            "center": "iina",
            "payload": {
                "kind": "configure",
                "secret": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                "portStart": 43191,
                "portEnd": 43200
            }
        }))
        .unwrap();

        assert!(matches!(
            input,
            ParentInput::Iina(iina_protocol::ParentInput::Configure { .. })
        ));
    }

    #[test]
    fn output_preserves_center_namespace() {
        let output = ParentOutput::Iina(iina_protocol::ParentOutput::Ready {
            protocol_version: 1,
            port: 43_191,
        });
        assert_eq!(
            serde_json::to_value(output).unwrap(),
            json!({
                "center": "iina",
                "payload": {
                    "kind": "ready",
                    "protocolVersion": 1,
                    "port": 43191
                }
            })
        );
    }
}
