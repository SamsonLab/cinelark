# CineLark Playback Bridge Protocol

- **Status:** Draft
- **Protocol version:** 1
- **Security status:** Blocked pending pairing-key provisioning and network
  exposure validation

The bridge is a provider-neutral protocol between CineLark for Mac and the
CineLark IINA plugin. It transports opaque playback capabilities and player
state; it does not expose a media-provider API.

## 1. Roles

- **Coordinator:** CineLark for Mac. Owns provider state, logical playback
  sessions, resume policy, and progress writes.
- **Player:** CineLark IINA Bridge. Owns one or more IINA player instances and
  maps commands/events to IINA/mpv.

CineLark Remote talks to the Coordinator, not the Player.

## 2. Transport

The candidate MVP transport is an IINA-hosted WebSocket server because the
public plugin API exposes `createServer`, `startServer`, connection callbacks,
and `sendText`.

The audited IINA implementation has important constraints:

- no TLS support
- no API to select a loopback-only interface
- `includePeerToPeer` is enabled
- no exported server-stop method
- `sendText` currently emits a WebSocket **binary** frame containing UTF-8

Therefore clients must accept UTF-8 in text or binary frames, and the bridge
must not ship based on assumed localhost isolation.

## 3. Security invariants

1. Every connection is unauthorized until mutual authentication succeeds.
2. Every accepted message is integrity-protected and replay-resistant.
3. Pairing secrets are random, revocable, and stored in Keychain by both sides.
4. Provider credentials never cross the bridge.
5. Playback URLs are redacted before any log formatting.
6. Unauthorized peers receive no player state, URL, title, or diagnostic detail.
7. Authentication failure closes or quarantines the connection and is
   rate-limited.

### Open blocker `BRIDGE-SEC-001`

Select and prototype pairing-key provisioning before implementing production
transport. The preferred outcome is an upstream IINA API that can bind the
server to loopback. A pre-shared high-entropy key with nonce-based HMAC may
provide defense in depth, but its provisioning UX and threat model still need
review. A six-digit code sent over unauthenticated cleartext is not sufficient.

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
- `mac` is calculated using the security design selected for
  `BRIDGE-SEC-001`; canonicalization is not frozen yet.
- Unknown message types are rejected with `bridge.error` but do not terminate a
  compatible connection.

The example authenticator is synthetic.

## 5. Commands: Coordinator → Player

### `bridge.hello`

Negotiates protocol and implementation versions and proves possession of the
pairing key. Exact payload is blocked by `BRIDGE-SEC-001`.

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

A state snapshot contains no playback URL:

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

The plugin may emit position changes frequently. The Coordinator throttles
external provider writes independently.

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
| App connection | `ws.*` server API |

## 8. Compatibility

- Both sides advertise protocol version and implementation version.
- Version 1 rejects unsupported major protocol versions.
- New optional payload members are ignored.
- Removing/renaming a field or changing units requires a new protocol version.
- Seconds are finite, non-negative JSON numbers; `NaN` and infinity are invalid.

## 9. Conformance tests

Before release, both sides must share vectors for:

- schema validation and unknown optional fields
- text and UTF-8 binary WebSocket frames
- authentication, replay, sequence gaps, and revocation
- stale playback sessions
- open/file-loaded/resume ordering
- pause, seek, EOF, replacement, close, and termination
- URL/header/title redaction
- reconnect and state resynchronization
