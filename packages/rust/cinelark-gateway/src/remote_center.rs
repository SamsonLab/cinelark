use std::{net::SocketAddr, sync::Arc};

use anyhow::{Result, bail};
use axum_server::Handle;
use tokio::task::JoinHandle;

use crate::{
    remote_gateway::{GatewayState, bind_available, serve},
    remote_identity::GatewayIdentity,
    remote_protocol::{PROTOCOL_VERSION, ParentInput, ParentOutput},
};

pub struct RemoteGatewayCenter {
    output: tokio::sync::mpsc::UnboundedSender<ParentOutput>,
    running: Option<RunningGateway>,
}

struct RunningGateway {
    state: Arc<GatewayState>,
    handle: Handle<SocketAddr>,
    server: JoinHandle<Result<()>>,
}

impl RemoteGatewayCenter {
    pub fn new(output: tokio::sync::mpsc::UnboundedSender<ParentOutput>) -> Self {
        Self {
            output,
            running: None,
        }
    }

    pub async fn handle(&mut self, input: ParentInput) -> Result<()> {
        match input {
            ParentInput::Configure {
                service_id,
                name,
                port_start,
                port_end,
                identity,
                devices,
            } => {
                self.start(service_id, name, port_start, port_end, identity, devices)
                    .await
            }
            ParentInput::Shutdown => {
                self.stop().await;
                Ok(())
            }
            command => {
                let Some(running) = &self.running else {
                    bail!("Remote gateway is not configured");
                };
                Self::handle_running(&running.state, command).await
            }
        }
    }

    async fn start(
        &mut self,
        service_id: String,
        name: String,
        port_start: u16,
        port_end: u16,
        identity: Option<crate::remote_identity::IdentityMaterial>,
        devices: Vec<crate::remote_protocol::DeviceConfiguration>,
    ) -> Result<()> {
        if self.running.is_some() {
            bail!("Remote gateway is already configured");
        }
        let (identity, generated) = match identity {
            Some(material) => (GatewayIdentity::from_material(material)?, false),
            None => (GatewayIdentity::generate()?, true),
        };
        if generated {
            let _ = self.output.send(ParentOutput::IdentityGenerated {
                identity: identity.material.clone(),
                fingerprint: identity.fingerprint.clone(),
            });
        }

        let state = GatewayState::new(service_id, name, devices, self.output.clone())?;
        let (listener, port) = bind_available(port_start, port_end)?;
        let handle = Handle::<SocketAddr>::new();
        let server_handle = handle.clone();
        let fingerprint = identity.fingerprint.clone();
        let server = tokio::spawn(serve(listener, identity, Arc::clone(&state), server_handle));
        handle.listening().await;
        self.running = Some(RunningGateway {
            state,
            handle,
            server,
        });
        let _ = self.output.send(ParentOutput::Ready {
            protocol_version: PROTOCOL_VERSION,
            port,
            fingerprint,
        });
        Ok(())
    }

    async fn handle_running(state: &GatewayState, input: ParentInput) -> Result<()> {
        match input {
            ParentInput::StartPairing {
                secret,
                expires_at_unix_milliseconds,
            } => {
                state
                    .start_pairing(secret, expires_at_unix_milliseconds)
                    .await
            }
            ParentInput::StopPairing => {
                state.stop_pairing().await;
                Ok(())
            }
            ParentInput::ApprovePairing {
                connection_id,
                device_id,
                credential,
                capabilities,
            } => {
                state
                    .approve_pairing(&connection_id, device_id, credential, capabilities)
                    .await
            }
            ParentInput::RejectPairing {
                connection_id,
                code,
            } => state.reject_pairing(&connection_id, code).await,
            ParentInput::Send {
                connection_id,
                message_type,
                reply_to,
                revision,
                payload,
            } => {
                state
                    .send(&connection_id, message_type, reply_to, revision, payload)
                    .await
            }
            ParentInput::Broadcast {
                message_type,
                revision,
                payload,
            } => {
                state.broadcast(message_type, revision, payload).await;
                Ok(())
            }
            ParentInput::RevokeDevice { device_id } => {
                state.revoke_device(&device_id).await;
                Ok(())
            }
            ParentInput::Configure { .. } | ParentInput::Shutdown => {
                bail!("invalid Remote gateway state transition")
            }
        }
    }

    pub async fn stop(&mut self) {
        let Some(running) = self.running.take() else {
            return;
        };
        running.handle.shutdown();
        let _ = running.server.await;
    }
}
