mod framing;
mod iina_broker;
mod iina_center;
mod iina_protocol;
mod parent_protocol;
mod remote_center;
mod remote_gateway;
mod remote_identity;
mod remote_protocol;

use anyhow::Result;
use parent_protocol::{ParentInput, ParentOutput};
use tokio::{io, sync::mpsc};

use crate::{iina_center::IINABridgeCenter, remote_center::RemoteGatewayCenter};

#[tokio::main]
async fn main() -> Result<()> {
    let (output, mut output_rx) = mpsc::unbounded_channel::<ParentOutput>();
    let writer = tokio::spawn(async move {
        let mut stdout = io::stdout();
        while let Some(frame) = output_rx.recv().await {
            if framing::write_frame(&mut stdout, &frame).await.is_err() {
                break;
            }
        }
    });

    let (iina_output, mut iina_output_rx) = mpsc::unbounded_channel();
    let iina_parent_output = output.clone();
    let iina_forwarder = tokio::spawn(async move {
        while let Some(frame) = iina_output_rx.recv().await {
            if iina_parent_output.send(ParentOutput::Iina(frame)).is_err() {
                break;
            }
        }
    });

    let (remote_output, mut remote_output_rx) = mpsc::unbounded_channel();
    let remote_parent_output = output.clone();
    let remote_forwarder = tokio::spawn(async move {
        while let Some(frame) = remote_output_rx.recv().await {
            if remote_parent_output
                .send(ParentOutput::Remote(frame))
                .is_err()
            {
                break;
            }
        }
    });

    let mut iina = IINABridgeCenter::new(iina_output.clone());
    let mut remote = RemoteGatewayCenter::new(remote_output.clone());
    let mut stdin = io::stdin();

    while let Some(input) = framing::read_frame::<_, ParentInput>(&mut stdin).await? {
        let result = match input {
            ParentInput::Iina(input) => iina.handle(input).await.inspect_err(|_| {
                let _ = iina_output.send(crate::iina_protocol::ParentOutput::Error {
                    code: "invalid_parent_command",
                    message: "The Mac sent an invalid IINA bridge command.",
                });
            }),
            ParentInput::Remote(input) => remote.handle(input).await.inspect_err(|_| {
                let _ = remote_output.send(crate::remote_protocol::ParentOutput::Error {
                    code: "invalidParentCommand",
                    message: "The Mac sent an invalid Remote gateway command.",
                });
            }),
            ParentInput::Process(parent_protocol::ProcessInput::Shutdown) => break,
        };
        if let Err(error) = result {
            eprintln!("[gateway] center_command_failed error={error:#}");
        }
    }

    iina.stop().await;
    remote.stop().await;
    drop(iina);
    drop(remote);
    drop(iina_output);
    drop(remote_output);
    let _ = iina_forwarder.await;
    let _ = remote_forwarder.await;
    drop(output);
    let _ = writer.await;
    Ok(())
}
