# CineLark Playback Bridge Protocol

- **Status:** Draft; Phase 0 implementation available
- **Protocol version:** 1
- **Security status:** Keychain/HMAC design implemented; signed-build validation pending

The bridge is a provider-neutral protocol carried through a bundled Rust helper
between CineLark for Mac and the CineLark IINA plugin. It transports opaque
playback capabilities and player state; it does not expose a media-provider API.

## 1. Roles

- **Coordinator:** CineLark for Mac. Owns provider state, logical playback
  sessions, resume policy, and progress writes.
- **Broker:** bundled `CineLarkBridge` Rust helper. Owns process isolation,
  envelope validation, ordering, authentication, and loopback transport.
- **Player:** thin IINA JavaScript plugin. Owns one or more IINA player instances
  and maps commands/events to IINA/mpv.

CineLark Remote talks to the Coordinator, not the Player.

## 2. Transport

Preferred topology:

```text
Mac app ⇄ child stdin/stdout ⇄ bundled Rust helper ⇄ loopback HTTP ⇄ IINA plugin
```

- The Mac app launches and supervises the helper; framed JSON over private child
  stdio requires no app-facing listener.
- The helper binds HTTP explicitly to `127.0.0.1` and `::1`, selects a port
  automatically, and accepts only authenticated plugin traffic.
- The IINA plugin uses its public outbound `http` API for bounded command
  long-poll and event POST requests.
- The helper terminates with CineLark and is never a launch daemon or separately
  installed service.

The audited IINA WebSocket server remains a non-default fallback because it has
no TLS, exposes no loopback bind option, enables peer-to-peer networking, and
cannot be stopped through JavaScript.

## 3. Security invariants

1. Every connection is unauthorized until mutual authentication succeeds.
2. Every accepted message is integrity-protected and replay-resistant.
3. Pairing secrets are random, revocable, and stored in Keychain by both sides.
4. Provider credentials never cross the bridge.
5. Playback URLs are redacted before any log formatting.
6. Unauthorized peers receive no player state, URL, title, or diagnostic detail.
7. Authentication failure closes or quarantines the connection and is
   rate-limited.

### `BRIDGE-SEC-001` Phase 0 resolution

[ADR-0004](../decisions/0004-iina-bridge-pairing.md) defines the implemented
pairing and local-process threat model. CineLark provisions a random 256-bit key
through macOS Keychain for the IINA-prefixed plugin service. IINA's Keychain
approval prompt is the one-time user authorization step. The key never enters a
plugin file, preference, process argument, environment variable, or HTTP
bootstrap response.

Production release remains gated on signed/notarized Keychain ACL validation,
revocation UI, denial/recovery testing, and stock-IINA lifecycle testing.

## 4. Envelope

All messages conform to
[`specs/bridge/envelope.schema.json`](../../specs/bridge/envelope.schema.json):

```json
{
  "protocolVersion": 1,
  "id": "4ff6c27e-1415-473f-8764-451d6a3369cb",
  "type": "player.pause",
  "sentAt": "2026-08-20T03:09:00Z",
  "sessionID": "6f55936d-5950-44fd-a696-f989d41785cc",
  "sequence": 42,
  "payload": {},
  "mac": "<base64url-authenticator>"
}
```

- `id` uniquely identifies one message.
- `sessionID` identifies a logical playback session and is omitted only for
  bridge-level messages.
- `sequence` is monotonically increasing within an authenticated connection.
- `mac` is unpadded base64url HMAC-SHA-256 over newline-separated protocol
  version, ID, type, timestamp, session ID, reply ID, sequence, and recursively
  key-sorted compact JSON payload.
- Plugin HTTP requests independently authenticate method, request target,
  Unix timestamp, and nonce with HMAC-SHA-256. The helper accepts a 30-second
  clock window and rejects reused nonces.
- Unknown message types are rejected with `bridge.error` but do not terminate a
  compatible connection.

The example authenticator is synthetic.

## 5. Commands: Coordinator → Player

### `bridge.hello`

Negotiates protocol and implementation versions and proves possession of the
Keychain-provisioned pairing key through both request and envelope HMACs.

### `player.play`

```json
{
  "playbackID": "f630df0d-d980-4a18-97de-277a59f82bd8",
  "url": "https://media.example/play/video/example?token=<redacted>",
  "title": "Example Title",
  "startPositionSeconds": 123.5,
  "presentation": {
    "fullscreen": true
  }
}
```

The URL is opaque to the plugin. The player acknowledges receipt, opens it, and
applies resume only after the matching file-loaded event. Actual URLs must never
appear in fixtures or logs.

### Transport commands

| Type | Payload |
| --- | --- |
| `player.pause` | `{}` |
| `player.resume` | `{}` |
| `player.stop` | `{}` |
| `player.seekRelative` | `{ "seconds": number, "exact": boolean }` |
| `player.seekAbsolute` | `{ "seconds": number }` |
| `player.setSpeed` | `{ "speed": number }` |
| `player.setVolume` | `{ "volume": number }` |
| `player.setMuted` | `{ "muted": boolean }` |
| `player.selectAudioTrack` | `{ "id": integer }` |
| `player.selectSubtitleTrack` | `{ "id": integer }` |
| `player.requestState` | `{}` |

Commands with a stale `sessionID` must be rejected rather than applied to the
current player.

## 6. Events: Player → Coordinator

| Type | Purpose |
| --- | --- |
| `bridge.ready` | negotiated versions and player availability |
| `bridge.error` | redacted protocol or command error |
| `player.fileLoaded` | selected URL loaded; URL itself is omitted |
| `player.stateChanged` | idle/playing/paused/stopped state |
| `player.positionChanged` | current position and duration in seconds |
| `player.tracksChanged` | audio/subtitle/video track inventory |
| `player.ended` | natural EOF with mpv reason when available |
| `player.closed` | window/plugin/application lifecycle ended |

A state snapshot contains no playback URL and maps to the shared semantics in
[`specs/common/playback.schema.json`](../../specs/common/playback.schema.json):

```json
{
  "state": "playing",
  "positionSeconds": 123.5,
  "durationSeconds": 7200.0,
  "speed": 1.0,
  "volume": 75.0,
  "muted": false
}
```

The plugin samples position every second and emits at most once every two
seconds. The Coordinator currently coalesces provider progress writes to a
10-second cadence and sends a terminal stopped update on EOF, close, stop, or
session replacement.

## 7. IINA mapping

| Bridge operation | IINA public plugin API |
| --- | --- |
| Create managed player | `global.createPlayerInstance(options)` |
| Open URL | `core.open(url)` or managed-player `url` option |
| Pause/resume/stop | `core.pause/resume/stop()` |
| Seek | `core.seek` / `core.seekTo` |
| State | `core.status.*` and mpv properties |
| Tracks | `core.audio/subtitle/video` |
| Lifecycle | `event.on("iina.*")`, `event.on("mpv.*")` |
| Helper connection | outbound `http.*` to loopback helper |

## 8. Compatibility

- Coordinator, Broker, and Player advertise protocol and implementation versions.
- Version 1 rejects unsupported major protocol versions.
- New optional payload members are ignored.
- Removing/renaming a field or changing units requires a new protocol version.
- Seconds are finite, non-negative JSON numbers; `NaN` and infinity are invalid.

## 9. Conformance tests

Before release, both sides must share vectors for:

- schema validation and unknown optional fields
- child stdio framing and loopback HTTP request/response limits
- authentication, replay, sequence gaps, and revocation
- stale playback sessions
- open/file-loaded/resume ordering
- pause, seek, EOF, replacement, close, and termination
- URL/header/title redaction
- long-poll latency, helper/plugin reconnect, and state resynchronization
