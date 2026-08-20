#!/usr/bin/env python3

"""Exercise framed stdio and authenticated loopback HTTP against the Rust broker."""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
from pathlib import Path
import struct
import subprocess
import time
import urllib.request
import uuid


def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode().rstrip("=")


def canonical(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def envelope_signing_input(value: dict) -> str:
    return "\n".join(
        [
            str(value["protocolVersion"]),
            value["id"],
            value["type"],
            value["sentAt"],
            value.get("sessionID", ""),
            value.get("replyTo", ""),
            str(value["sequence"]),
            canonical(value["payload"]),
        ]
    )


def envelope(secret: bytes, message_type: str, sequence: int, payload: dict, session_id: str | None = None) -> dict:
    value = {
        "protocolVersion": 1,
        "id": str(uuid.uuid4()),
        "type": message_type,
        "sentAt": "2026-08-20T03:09:00Z",
        "sequence": sequence,
        "payload": payload,
        "mac": "",
    }
    if session_id:
        value["sessionID"] = session_id
    signing_input = envelope_signing_input(value)
    value["mac"] = b64url(hmac.new(secret, signing_input.encode(), hashlib.sha256).digest())
    return value


def write_frame(process: subprocess.Popen[bytes], value: dict) -> None:
    payload = json.dumps(value, separators=(",", ":")).encode()
    assert process.stdin
    process.stdin.write(struct.pack(">I", len(payload)) + payload)
    process.stdin.flush()


def read_exact(stream, count: int) -> bytes:
    value = b""
    while len(value) < count:
        chunk = stream.read(count - len(value))
        if not chunk:
            raise RuntimeError("bridge closed its output")
        value += chunk
    return value


def read_frame(process: subprocess.Popen[bytes]) -> dict:
    assert process.stdout
    size = struct.unpack(">I", read_exact(process.stdout, 4))[0]
    return json.loads(read_exact(process.stdout, size))


def request(secret: bytes, base_url: str, method: str, uri: str, body: dict | None = None):
    timestamp = int(time.time())
    nonce = f"synthetic-{uuid.uuid4().hex}"
    signing_input = f"{method}\n{uri}\n{timestamp}\n{nonce}"
    headers = {
        "X-CineLark-Timestamp": str(timestamp),
        "X-CineLark-Nonce": nonce,
        "X-CineLark-Signature": b64url(hmac.new(secret, signing_input.encode(), hashlib.sha256).digest()),
    }
    data = None
    if body is not None:
        data = json.dumps(body, separators=(",", ":")).encode()
        headers["Content-Type"] = "application/json"
    with urllib.request.urlopen(
        urllib.request.Request(base_url + uri, data=data, headers=headers, method=method),
        timeout=5,
    ) as response:
        content = response.read()
        return response.status, json.loads(content) if content else None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", required=True, type=Path)
    arguments = parser.parse_args()

    secret = bytes(range(32))
    process = subprocess.Popen(
        [str(arguments.executable)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        write_frame(
            process,
            {
                "kind": "configure",
                "secret": b64url(secret),
                "portStart": 44201,
                "portEnd": 44220,
            },
        )
        ready = read_frame(process)
        assert ready["kind"] == "ready"
        assert 44201 <= ready["port"] <= 44220
        base_url = f"http://127.0.0.1:{ready['port']}"

        with urllib.request.urlopen(base_url + "/v1/health", timeout=5) as response:
            health = json.load(response)
        assert health["protocolVersion"] == 1

        session_id = str(uuid.uuid4())
        play = envelope(
            secret,
            "player.play",
            1,
            {
                "playbackID": session_id,
                "url": "https://media.example/video?token=<redacted>",
                "title": "Synthetic Feature",
                "startPositionSeconds": 12.5,
                "presentation": {"fullscreen": False},
            },
            session_id,
        )
        write_frame(process, {"kind": "command", "envelope": play})

        hello = envelope(secret, "bridge.hello", 0, {"pluginVersion": "0.1.0"})
        status, response = request(secret, base_url, "POST", "/v1/plugin/hello", hello)
        assert status == 200 and response["protocolVersion"] == 1
        forwarded = read_frame(process)
        assert forwarded["kind"] == "event", (
            forwarded,
            b64url(hashlib.sha256(envelope_signing_input(play).encode()).digest()),
        )
        assert forwarded["envelope"]["type"] == "bridge.hello"

        status, response = request(secret, base_url, "GET", "/v1/plugin/commands?after=0")
        assert status == 200
        assert [item["type"] for item in response["commands"]] == ["player.play"]
        assert response["commands"][0]["payload"]["playbackID"] == session_id

        write_frame(process, {"kind": "shutdown"})
        process.stdin.close()
        assert process.wait(timeout=5) == 0
    except Exception:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
        if process.stderr:
            diagnostics = process.stderr.read().decode(errors="replace").strip()
            if diagnostics:
                print(diagnostics)
        raise
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
    print("Bridge process integration passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
