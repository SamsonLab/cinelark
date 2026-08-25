# CineLark Couch Remote Protocol

- **Status:** Implemented version 1
- **Participants:** Flutter CineLark Remote, Rust Remote Gateway, CineLark for Mac
- **Initial targets:** iOS and Android on the same local network as the Mac

This protocol makes the phone a secure, context-aware control surface for the
authoritative Mac application. It covers pairing, remote login, semantic
navigation, search text entry, and advanced IINA playback control. It is not a
provider API, a generic keyboard protocol, or a mobile playback protocol.

## 1. Boundary rules

1. The Mac owns provider credentials, provider requests, navigation/focus,
   playback descriptors, episode continuity, progress writes, and command
   authorization.
2. The Flutter Remote owns paired-device material, transient user input, local
   presentation state, and reconnect behavior.
3. The Rust Remote Gateway owns TLS/WebSocket transport, frame limits, pairing
   expiry, device proof verification, sequencing, rate limits, and private stdio
   forwarding. It cannot perform product operations.
4. Remote sends semantic commands; it never injects raw platform key codes or
   talks directly to IINA.
5. Provider headers, cookies, DTOs, playback URLs, bridge secrets, filesystem
   paths, and raw diagnostic errors never cross this boundary.
6. CineLark works identically when no Remote is paired or connected.

## 2. Transport architecture

```text
Flutter Remote
    │ pinned WSS on LAN
    ▼
CineLarkRemoteGateway (bundled Rust child)
    │ private length-prefixed JSON stdio
    ▼
CineLark RemoteGatewayCoordinator (Mac authority)
    ├── semantic navigation dispatcher
    ├── AppModel / provider login
    └── PlaybackCoordinator → CineLarkBridge → IINA
```

The Rust Remote Gateway is a separate executable and trust domain from the
loopback-only IINA bridge. They never reuse ports, secrets, device records, or
session authentication.

The WebSocket endpoint is:

```text
wss://<endpoint-hint>:<port>/v1/remote
```

Version 1 does not negotiate a `Sec-WebSocket-Protocol` value; protocol version
negotiation stays inside the authenticated envelope. Cleartext fallback is
forbidden.

## 3. Discovery and QR payload

The Mac advertises its candidate endpoint with Bonjour/mDNS:

```text
Service type: _cinelark._tcp
```

TXT records contain only non-secret negotiation hints:

```text
serviceID=<opaque-uuid>
name=<user-visible-mac-name>
protocolMin=1
protocolMax=1
tls=required
```

An explicit Mac pairing window also displays a QR code conforming to
[`specs/remote/pairing.schema.json`](../../specs/remote/pairing.schema.json).
It contains protocol version, service ID/name, host and port hints, the SHA-256
certificate fingerprint, a 256-bit single-use secret, and expiry.

The endpoint is never identity. Flutter accepts the self-signed TLS certificate
only when its DER fingerprint exactly matches the QR pin. The gateway supports
TLS 1.2 and TLS 1.3 so the Android 10 baseline can establish the pinned session.

The initial Flutter client uses the QR host and port for pairing and reconnect.
The Mac writes its preferred active numeric IPv4 address rather than relying on
`.local` resolution, which is not available on every supported Android device.
On Android, the WSS socket is created from the active non-VPN Wi-Fi `Network`
so a device-wide VPN cannot divert the local Mac connection into its tunnel.
The Android-native TLS trust manager applies the same exact DER SHA-256
certificate pin before accepting that socket.
Bonjour-based endpoint recovery is additive future work; it cannot replace
certificate pinning or device authentication.

The QR payload is sensitive. It must not enter logs, screenshots, analytics,
pasteboards, backups, crash reports, or fixtures.

## 4. First-time pairing

1. The user opens **Pair New Remote** on the Mac.
2. Mac creates a 256-bit single-use secret with a five-minute expiry,
   configures the Rust gateway, and displays the QR.
3. Flutter scans the QR, opens pinned WSS, and receives `session.challenge`.
4. Flutter sends `pairing.request` with the QR secret, a locally generated
   device ID, and a user-visible device name.
5. Rust validates and immediately consumes the secret, sends `pairing.pending`,
   and forwards one sanitized approval request to Mac.
6. Mac displays the device and requires explicit approval.
7. Mac generates a 256-bit device credential, persists its paired-device record,
   and sends `approvePairing` over private stdio.
8. Rust sends `pairing.approved` with the credential and granted capabilities.
9. Flutter stores the credential in Keychain/Keystore and erases the QR secret.
10. Mac erases the pairing window; the secret cannot pair a second device.

Pairing rejection closes the WSS connection. A new attempt requires a new Mac
pairing window.

## 5. Subsequent authentication

Every WSS connection starts with:

```json
{
  "type": "session.challenge",
  "payload": {
    "connectionID": "8dc63877-bf80-4d63-afc0-bec50d1ecb60",
    "serviceID": "ad54e7ba-9409-4f54-8c7c-65e781978cf9",
    "nonce": "<base64url-256-bit>",
    "protocolMin": 1,
    "protocolMax": 1
  }
}
```

Flutter responds with `session.authenticate` containing `deviceID` and:

```text
proof = Base64URL(HMAC-SHA256(
    deviceCredential,
    UTF8(serviceID + "\n" + connectionID + "\n" + nonce)
))
```

The deterministic cross-runtime vector is
[`remote-authentication-vector.json`](../../fixtures/conformance/remote-authentication-vector.json).

Rust verifies the proof against device material supplied by Mac at process
configuration. The raw device credential is not sent during reconnect. Mac then
sends `session.ready` and full snapshots. Revoked or unknown devices receive a
stable error and the connection closes.

## 6. Envelope and ordering

Messages conform to
[`specs/remote/envelope.schema.json`](../../specs/remote/envelope.schema.json):

```json
{
  "protocolVersion": 1,
  "id": "d2ab79fc-95f0-46de-a21c-9943b7aa66c7",
  "type": "playback.seekRelative",
  "sentAt": "2026-08-20T03:09:00Z",
  "sequence": 31,
  "revision": 84,
  "payload": {
    "playbackID": "6f55936d-5950-44fd-a696-f989d41785cc",
    "seconds": 30.0
  }
}
```

- Sequence numbers start at zero and increase exactly by one per sender on each
  connection. WebSocket is ordered; gaps and duplicates are rejected.
- Reconnect creates a new sequence space and is followed by full snapshots.
- `id` and `replyTo` correlate commands and acknowledgements.
- `revision` is the authoritative Mac state revision that produced a snapshot
  or against which a state-sensitive command was issued.
- Rust assigns server-side envelope sequences so gateway-generated and Mac
  messages share one ordered stream.
- Maximum Remote JSON message size is 64 KiB; private stdio frames are bounded
  separately at 1 MiB.

## 7. Capability negotiation

`session.ready` includes the negotiated protocol and granted capabilities:

```text
auth.remoteEntry
navigation.basic
navigation.sections
textInput.remote
playback.transport
playback.seek
playback.rate
playback.fullscreen
playback.episodeNavigation
playback.trackSelection
playback.closeAndActivate
audio.volume
```

Capabilities change with Mac state and playback/backend support. Flutter hides
or disables unavailable controls; the Mac still rejects unsupported commands.

## 8. Remote commands

### 8.1 Application and snapshots

| Type | Payload |
| --- | --- |
| `app.requestSnapshot` | `{}` |
| `app.activate` | `{}` |

### 8.2 Dedicated remote login

| Type | Payload |
| --- | --- |
| `auth.submitCredentials` | `{ "username": string, "password": string, "totpCode"?: string }` |

This command is accepted only for an authenticated device while Mac is signed
out and advertises `auth.remoteEntry`. It is never represented as a generic text
session. Flutter edits values locally and submits once. Phone and gateway erase
the payload after forwarding; Mac diagnostic redaction is selected by message
type before any value formatting.

Mac responds with a redacted `auth.result` and a new app snapshot. Rate limiting
is applied independently of general command throughput.

### 8.3 Navigation

| Type | Payload |
| --- | --- |
| `navigation.move` | `{ "direction": "up|down|left|right" }` |
| `navigation.select` | `{}` |
| `navigation.back` | `{}` |
| `navigation.openSection` | `{ "section": "home|movies|series|favorites|search" }` |

These enter the same semantic dispatcher used by `NSEvent`. Wire messages never
address SwiftUI view identities or physical key codes.

### 8.4 Text input

| Type | Payload |
| --- | --- |
| `textInput.update` | `{ "sessionID": uuid, "revision": integer, "text": string }` |
| `textInput.commit` | `{ "sessionID": uuid, "revision": integer }` |
| `textInput.cancel` | `{ "sessionID": uuid, "revision": integer }` |

Mac publishes at most one active `textInput.snapshot` with kind, initial/current
text, maximum length, and revision. A page change or cancel closes the session;
search commit triggers an immediate search while keeping that search session
available for another query. Stale session IDs and revisions are rejected.
Search updates may also produce debounced previews.

### 8.5 Playback and audio

All state-sensitive commands carry the current `playbackID`. Track selection and
episode navigation also carry the latest playback snapshot revision.

| Type | Additional payload |
| --- | --- |
| `playback.togglePause` | `{}` |
| `playback.pause` | `{}` |
| `playback.resume` | `{}` |
| `playback.stop` | `{}` |
| `playback.seekRelative` | `{ "seconds": number, "exact"?: boolean }` |
| `playback.seekAbsolute` | `{ "seconds": number }` |
| `playback.setRate` | `{ "rate": number }` |
| `playback.setFullscreen` | `{ "fullscreen": boolean }` |
| `playback.playPrevious` | `{ "revision": integer }` |
| `playback.playNext` | `{ "revision": integer }` |
| `playback.selectAudioTrack` | `{ "trackID": integer, "revision": integer }` |
| `playback.selectSubtitleTrack` | `{ "trackID": integer|null, "revision": integer }` |
| `playback.closeAndActivateApp` | `{}` |
| `playback.requestSnapshot` | `{}` |
| `audio.setVolume` | `{ "volume": number }` |
| `audio.adjustVolume` | `{ "delta": number }` |
| `audio.setMuted` | `{ "muted": boolean }` |

Previous/next is a CineLark episode-continuity operation, not an IINA playlist
operation. `closeAndActivateApp` finalizes progress, closes the managed player,
and activates CineLark as one semantic Mac operation.

Flutter previews scrubbing locally and commits a bounded absolute seek. It does
not emit one command per pointer pixel.

## 9. Mac snapshots and events

| Type | Purpose |
| --- | --- |
| `session.ready` | Negotiated protocol, capabilities, and device state |
| `app.snapshot` | Mac phase, selected section, available surfaces, and safe error code |
| `textInput.snapshot` | Active non-sensitive text session or `null` |
| `auth.result` | Accepted/succeeded plus stable redacted error code |
| `playback.snapshot` | Sanitized player, episode-navigation, and track state |
| `capabilities.changed` | Current command availability |
| `command.ack` | Accepted/rejected independently from resulting state |
| `session.error` | Stable redacted protocol/authorization error |
| `session.revoked` | Device credential was revoked |

Playback snapshots follow
[`specs/common/playback.schema.json`](../../specs/common/playback.schema.json).
Track IDs are scoped to one playback ID. Artwork, when implemented, is served by
an authenticated bounded Mac endpoint or embedded bounded data; provider URLs
and bearer playback URLs remain forbidden.

## 10. Synchronization invariants

- Mac sends full app, text-input, playback, and capability snapshots after
  authentication and reconnect.
- Playback and text-input revisions are monotonic within their scoped Mac
  sessions. Flutter ignores stale playback snapshots and requests full state
  after a stale-revision rejection.
- Mac serializes accepted semantic commands on `MainActor`.
- Command acknowledgement means accepted for execution, not that the resulting
  state has already been observed.
- Connection loss never changes playback, commits text, or submits login.
- While Flutter is scrubbing, it previews local position and reconciles only
  after the committed seek produces a newer playback snapshot.
- Episode replacement invalidates all outgoing track and transport commands
  scoped to the previous playback ID.

## 11. Stable errors

```text
unsupportedProtocol
unsupportedCapability
unauthenticated
revoked
pairingUnavailable
pairingRejected
invalidMessage
staleSequence
staleRevision
invalidState
rateLimited
internal
```

No raw Swift/Rust/Dart errors, provider response bodies, URLs, headers, or file
paths are serialized.

## 12. Shared conformance and validation

Shared schemas and sanitized vectors cover:

- envelope validation and unknown optional fields
- Remote authentication HMAC
- playback snapshots and finite-second validation
- valid and invalid Remote client messages

Automated Rust integration tests cover TLS 1.2 pinned WSS, framed pairing-time
decoding, one-time pairing consumption, explicit approval, authenticated
forwarding, sequence rejection, frame bounds, rate limits, stable error
redaction, and clean child-process lifecycle. Swift and
Dart tests cover shared authentication, TLS identity field compatibility, text
revision behavior, and envelope parsing. Physical-device sleep/wake and network
switching remain release smoke tests.

## 13. Future additions

- Bonjour endpoint recovery in Flutter
- authenticated artwork transfer/cache policy
- lock-screen/notification Remote controls

These additions do not change TLS pinning, explicit pairing, Mac authority,
semantic commands, or sensitive-value redaction.
