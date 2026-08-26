use anyhow::{Context, Result, bail};
use serde::{Serialize, de::DeserializeOwned};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

pub const MAX_FRAME_BYTES: usize = 1_048_576;

pub async fn read_frame<R, T>(reader: &mut R) -> Result<Option<T>>
where
    R: AsyncRead + Unpin,
    T: DeserializeOwned,
{
    let mut length_bytes = [0_u8; 4];
    match reader.read_exact(&mut length_bytes).await {
        Ok(_) => {}
        Err(error) if error.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(error) => return Err(error).context("read frame length"),
    }
    let length = u32::from_be_bytes(length_bytes) as usize;
    if length == 0 || length > MAX_FRAME_BYTES {
        bail!("invalid frame length");
    }
    let mut payload = vec![0_u8; length];
    reader
        .read_exact(&mut payload)
        .await
        .context("read frame payload")?;
    serde_json::from_slice(&payload)
        .context("decode frame")
        .map(Some)
}

pub async fn write_frame<W, T>(writer: &mut W, value: &T) -> Result<()>
where
    W: AsyncWrite + Unpin,
    T: Serialize,
{
    let payload = serde_json::to_vec(value).context("encode frame")?;
    if payload.is_empty() || payload.len() > MAX_FRAME_BYTES {
        bail!("invalid frame length");
    }
    writer
        .write_all(&(payload.len() as u32).to_be_bytes())
        .await
        .context("write frame length")?;
    writer
        .write_all(&payload)
        .await
        .context("write frame payload")?;
    writer.flush().await.context("flush frame")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::{Deserialize, Serialize};
    use tokio::io::duplex;

    #[derive(Debug, Deserialize, PartialEq, Serialize)]
    struct Example {
        value: String,
    }

    #[tokio::test]
    async fn framed_json_round_trips() {
        let (mut writer, mut reader) = duplex(1024);
        let send = Example {
            value: "remote".to_owned(),
        };
        write_frame(&mut writer, &send).await.unwrap();
        let received: Example = read_frame(&mut reader).await.unwrap().unwrap();
        assert_eq!(received, send);
    }

    #[tokio::test]
    async fn oversized_frames_are_rejected_before_allocation() {
        let (mut writer, mut reader) = duplex(16);
        writer
            .write_all(&((MAX_FRAME_BYTES + 1) as u32).to_be_bytes())
            .await
            .unwrap();
        let result: Result<Option<Example>> = read_frame(&mut reader).await;
        assert!(result.is_err());
    }
}
