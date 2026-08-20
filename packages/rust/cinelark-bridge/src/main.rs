mod broker;
mod framing;
mod protocol;

use std::{io, sync::mpsc, thread};

use broker::{BrokerState, bind_loopback_pair, router};
use protocol::{PROTOCOL_VERSION, ParentInput, ParentOutput, decode_secret};
use tokio::sync::mpsc as tokio_mpsc;

#[tokio::main]
async fn main() {
    if let Err(error) = run().await {
        eprintln!("CineLarkBridge terminated: {error}");
        std::process::exit(1);
    }
}

async fn run() -> io::Result<()> {
    let (output_sender, output_receiver) = mpsc::channel::<ParentOutput>();
    let writer = thread::spawn(move || {
        let stdout = io::stdout();
        let mut stdout = stdout.lock();
        while let Ok(output) = output_receiver.recv() {
            if framing::write_frame(&mut stdout, &output).is_err() {
                break;
            }
        }
    });

    let configuration = {
        let stdin = io::stdin();
        let mut stdin = stdin.lock();
        framing::read_frame::<ParentInput>(&mut stdin)?
    };

    let Some(ParentInput::Configure {
        secret,
        port_start,
        port_end,
    }) = configuration
    else {
        let _ = output_sender.send(ParentOutput::Error {
            code: "configuration_required",
            message: "The first parent frame must configure the broker.",
        });
        drop(output_sender);
        let _ = writer.join();
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "configuration required",
        ));
    };

    let Some(secret) = decode_secret(&secret) else {
        let _ = output_sender.send(ParentOutput::Error {
            code: "invalid_secret",
            message: "The bridge secret must contain 256 bits.",
        });
        drop(output_sender);
        let _ = writer.join();
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid secret",
        ));
    };

    let (port, ipv4_listener, ipv6_listener) = bind_loopback_pair(port_start, port_end)?;
    let state = BrokerState::new(secret, output_sender.clone());
    let app = router(state.clone());

    let ipv4_server = tokio::spawn(axum::serve(ipv4_listener, app.clone()).into_future());
    let ipv6_server = tokio::spawn(axum::serve(ipv6_listener, app).into_future());

    output_sender
        .send(ParentOutput::Ready {
            protocol_version: PROTOCOL_VERSION,
            port,
        })
        .map_err(|_| io::Error::new(io::ErrorKind::BrokenPipe, "parent output closed"))?;

    let (input_sender, mut input_receiver) = tokio_mpsc::channel::<ParentInput>(32);
    let _reader = thread::spawn(move || {
        let stdin = io::stdin();
        let mut stdin = stdin.lock();
        while let Ok(Some(input)) = framing::read_frame::<ParentInput>(&mut stdin) {
            if input_sender.blocking_send(input).is_err() {
                break;
            }
        }
    });

    while let Some(input) = input_receiver.recv().await {
        match input {
            ParentInput::Command { envelope } => {
                if let Err(code) = state.enqueue_command(envelope).await {
                    let _ = output_sender.send(ParentOutput::Error {
                        code,
                        message: "The parent command was rejected.",
                    });
                }
            }
            ParentInput::Shutdown => break,
            ParentInput::Configure { .. } => {
                let _ = output_sender.send(ParentOutput::Error {
                    code: "already_configured",
                    message: "The broker cannot be reconfigured while running.",
                });
            }
        }
    }

    ipv4_server.abort();
    ipv6_server.abort();
    let _ = ipv4_server.await;
    let _ = ipv6_server.await;
    drop(state);
    drop(output_sender);
    let _ = writer.join();
    Ok(())
}
