mod framing;
mod gateway;
mod identity;
mod protocol;

use std::{net::SocketAddr, sync::Arc};

use anyhow::{Context, Result, bail};
use axum_server::Handle;
use gateway::{GatewayState, bind_available, serve};
use identity::GatewayIdentity;
use protocol::{PROTOCOL_VERSION, ParentInput, ParentOutput};
use tokio::{io, sync::mpsc};

#[tokio::main]
async fn main() -> Result<()> {
    let mut stdin = io::stdin();
    let first = framing::read_frame::<_, ParentInput>(&mut stdin)
        .await?
        .context("Remote gateway requires configuration")?;
    let ParentInput::Configure {
        service_id,
        name,
        port_start,
        port_end,
        identity,
        devices,
    } = first
    else {
        bail!("first Remote gateway frame must configure the process");
    };
    eprintln!("[remote-gateway] configure_received");

    let (host_output, mut host_output_rx) = mpsc::unbounded_channel::<ParentOutput>();
    let writer = tokio::spawn(async move {
        let mut stdout = io::stdout();
        while let Some(output) = host_output_rx.recv().await {
            if framing::write_frame(&mut stdout, &output).await.is_err() {
                break;
            }
        }
    });

    let (identity, generated) = match identity {
        Some(material) => (GatewayIdentity::from_material(material)?, false),
        None => (GatewayIdentity::generate()?, true),
    };
    if generated {
        let _ = host_output.send(ParentOutput::IdentityGenerated {
            identity: identity.material.clone(),
            fingerprint: identity.fingerprint.clone(),
        });
    }

    let state = GatewayState::new(service_id, name, devices, host_output.clone())?;
    let (listener, port) = bind_available(port_start, port_end)?;
    let handle = Handle::<SocketAddr>::new();
    let server_handle = handle.clone();
    let fingerprint = identity.fingerprint.clone();
    let server = tokio::spawn(serve(listener, identity, Arc::clone(&state), server_handle));
    handle
        .listening()
        .await
        .context("start Remote TLS listener")?;
    eprintln!("[remote-gateway] tls_listener_ready port={port}");
    let _ = host_output.send(ParentOutput::Ready {
        protocol_version: PROTOCOL_VERSION,
        port,
        fingerprint,
    });

    while let Some(input) = framing::read_frame::<_, ParentInput>(&mut stdin).await? {
        let result = match input {
            ParentInput::Configure { .. } => Err(anyhow::anyhow!("gateway is already configured")),
            ParentInput::StartPairing {
                secret,
                expires_at_unix_milliseconds,
            } => {
                eprintln!("[remote-gateway] start_pairing_received");
                state
                    .start_pairing(secret, expires_at_unix_milliseconds)
                    .await
            }
            ParentInput::StopPairing => {
                eprintln!("[remote-gateway] stop_pairing_received");
                state.stop_pairing().await;
                Ok(())
            }
            ParentInput::ApprovePairing {
                connection_id,
                device_id,
                credential,
                capabilities,
            } => {
                eprintln!("[remote-gateway] approve_pairing_received");
                state
                    .approve_pairing(&connection_id, device_id, credential, capabilities)
                    .await
            }
            ParentInput::RejectPairing {
                connection_id,
                code,
            } => {
                eprintln!("[remote-gateway] reject_pairing_received code={code}");
                state.reject_pairing(&connection_id, code).await
            }
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
            ParentInput::Shutdown => break,
        };
        if let Err(error) = result {
            eprintln!("[remote-gateway] parent_command_failed error={error:#}");
            let _ = host_output.send(ParentOutput::Error {
                code: "invalidParentCommand",
                message: "The Mac sent an invalid Remote gateway command.",
            });
        }
    }

    handle.shutdown();
    eprintln!("[remote-gateway] shutdown_received");
    let _ = server.await;
    drop(state);
    drop(host_output);
    let _ = writer.await;
    Ok(())
}
