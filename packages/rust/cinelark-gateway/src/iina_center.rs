use anyhow::{Result, bail};
use tokio::task::JoinHandle;

use crate::{
    iina_broker::{BrokerState, bind_loopback_pair, router},
    iina_protocol::{PROTOCOL_VERSION, ParentInput, ParentOutput, decode_secret},
};

pub struct IINABridgeCenter {
    output: tokio::sync::mpsc::UnboundedSender<ParentOutput>,
    running: Option<RunningBridge>,
}

struct RunningBridge {
    state: BrokerState,
    ipv4_server: JoinHandle<std::io::Result<()>>,
    ipv6_server: JoinHandle<std::io::Result<()>>,
}

impl IINABridgeCenter {
    pub fn new(output: tokio::sync::mpsc::UnboundedSender<ParentOutput>) -> Self {
        Self {
            output,
            running: None,
        }
    }

    pub async fn handle(&mut self, input: ParentInput) -> Result<()> {
        match input {
            ParentInput::Configure {
                secret,
                port_start,
                port_end,
            } => self.start(secret, port_start, port_end).await,
            ParentInput::Command { envelope } => {
                let Some(running) = &self.running else {
                    bail!("IINA bridge is not configured");
                };
                running
                    .state
                    .enqueue_command(envelope)
                    .await
                    .map_err(anyhow::Error::msg)
            }
            ParentInput::Shutdown => {
                self.stop().await;
                Ok(())
            }
        }
    }

    async fn start(&mut self, secret: String, port_start: u16, port_end: u16) -> Result<()> {
        if self.running.is_some() {
            bail!("IINA bridge is already configured");
        }
        let Some(secret) = decode_secret(&secret) else {
            bail!("IINA bridge secret must contain 256 bits");
        };
        let (port, ipv4_listener, ipv6_listener) = bind_loopback_pair(port_start, port_end)?;
        let state = BrokerState::new(secret, self.output.clone());
        let app = router(state.clone());
        let ipv4_server = tokio::spawn(axum::serve(ipv4_listener, app.clone()).into_future());
        let ipv6_server = tokio::spawn(axum::serve(ipv6_listener, app).into_future());
        self.running = Some(RunningBridge {
            state,
            ipv4_server,
            ipv6_server,
        });
        let _ = self.output.send(ParentOutput::Ready {
            protocol_version: PROTOCOL_VERSION,
            port,
        });
        Ok(())
    }

    pub async fn stop(&mut self) {
        let Some(running) = self.running.take() else {
            return;
        };
        running.ipv4_server.abort();
        running.ipv6_server.abort();
        let _ = running.ipv4_server.await;
        let _ = running.ipv6_server.await;
    }
}
