# CineLark Remote Protocol

- **Status:** Draft; transport spike required before version 1 freeze
- **Participants:** CineLark for Mac and Flutter CineLark Remote
- **Initial targets:** iOS and Android

This protocol exposes a small, sanitized control surface from the authoritative
Mac app. It is not a provider API and is intentionally separate from the
Mac-to-IINA playback bridge.

## 1. Boundary rules

1. The Mac app owns provider, navigation, playback, and focus state.
2. Remote sends semantic commands; it does not manipulate SwiftUI views or IINA
   directly.
3. Remote receives only the state needed to render its experience.
4. Provider credentials, headers, cookies, DTOs, playback URLs, bridge secrets,
   and filesystem paths never cross this boundary.
5. Every device is explicitly paired, named, auditable, and revocable.
6. The Mac app works identically when no Remote exists.

## 2. Discovery

Candidate discovery uses Bonjour/mDNS:

```text
Service type: _cinelark._tcp
```

TXT records may advertise only non-secret negotiation data:

```text
serviceID=<opaque-uuid>
name=<user-visible-mac-name>
protocolMin=1
protocolMax=1
tls=required
```

The endpoint is a hint, not identity. Remote authenticates the Mac through its
paired certificate/public-key fingerprint. Discovery outside the local network
is out of scope.

Flutter must declare and explain platform local-network permissions. Discovery
is isolated behind a Dart interface so a platform channel can replace an
insufficient mDNS package without affecting features.

## 3. Transport

Recommended transport:

```text
WebSocket over TLS (WSS), hosted by CineLark for Mac
```

Reasons:

- bidirectional snapshots and commands
- native Swift and Flutter support
- message framing compatible with JSON Schema
- TLS protects device credentials and private now-playing data on LAN

The Phase 0 spike must validate `NWListener`/WebSocket interoperability,
certificate pinning, sleep/wake reconnect, and iOS/Android lifecycle behavior.
No cleartext fallback is allowed.

## 4. Pairing

### 4.1 First-time flow

1. User opens **Pair New Remote** on the Mac.
2. Mac creates a high-entropy, single-use pairing secret with a short expiry.
3. Mac displays a QR payload containing protocol version, service ID,
   certificate fingerprint, and pairing secret.
4. Remote scans locally, discovers the matching endpoint, establishes pinned
   TLS, and submits the one-time secret inside that channel.
5. Mac displays the requesting device and requires user confirmation.
6. Mac issues a device-scoped credential and records device name, ID, creation
   date, and last-seen date.
7. Both sides store credentials in Keychain/Keystore and erase pairing material.

Conceptual QR shape:

```text
cinelark://pair?v=1&service=<uuid>&fingerprint=<sha256>&secret=<random>
```

The real QR is sensitive and must not enter logs, screenshots, analytics, paste
boards, backups, or fixtures. A short numeric code sent over unauthenticated
cleartext is not an acceptable substitute.

### 4.2 Subsequent connections

- Remote pins the paired Mac identity and authenticates with its device-scoped
  credential over TLS.
- Mac checks revocation and allowed capabilities before sending a snapshot.
- Credential rotation is explicit and recoverable; failure returns to pairing
  rather than disabling TLS validation.

### 4.3 Revocation

The Mac exposes paired devices and supports individual/all-device revocation.
Remote handles revocation as an unauthenticated state and deletes obsolete local
credentials.

## 5. Envelope and negotiation

Messages conform to
[`specs/remote/envelope.schema.json`](../../specs/remote/envelope.schema.json):

```json
{
  "protocolVersion": 1,
  "id": "d2ab79fc-95f0-46de-a21c-9943b7aa66c7",
  "type": "playback.seekRelative",
  "sentAt": "2026-08-20T03:09:00Z",
  "sequence": 31,
  "payload": {
    "seconds": 30.0
  }
}
```

TLS protects transport integrity. `sequence` rejects duplicate/reordered
commands within one connection; `id` supports acknowledgements and diagnostics.

After authentication, peers exchange:

```json
{
  "implementation": "CineLark Remote",
  "implementationVersion": "0.1.0",
  "protocolMin": 1,
  "protocolMax": 1,
  "capabilities": [
    "navigation.basic",
    "playback.transport",
    "playback.seek",
    "audio.volume"
  ]
}
```

Behavior is gated by negotiated capabilities, not implementation version.

## 6. Commands: Remote → Mac

### Navigation

| Type | Payload |
| --- | --- |
| `navigation.move` | `{ "direction": "up|down|left|right" }` |
| `navigation.select` | `{}` |
| `navigation.back` | `{}` |
| `navigation.menu` | `{}` |

These map to the same semantic command layer used by local keyboard/remote
input. Remote does not address view IDs directly.

### Playback and audio

| Type | Payload |
| --- | --- |
| `playback.togglePause` | `{}` |
| `playback.pause` | `{}` |
| `playback.resume` | `{}` |
| `playback.stop` | `{}` |
| `playback.seekRelative` | `{ "seconds": number }` |
| `playback.seekAbsolute` | `{ "seconds": number }` |
| `audio.setVolume` | `{ "volume": number }` |
| `audio.adjustVolume` | `{ "delta": number }` |
| `audio.setMuted` | `{ "muted": boolean }` |
| `app.requestSnapshot` | `{}` |

Mac acknowledges command acceptance separately from resulting state. Commands
are rejected when their capability is unavailable or their sequence/session is
stale.

## 7. Events and snapshots: Mac → Remote

| Type | Purpose |
| --- | --- |
| `session.ready` | negotiated protocol and capabilities |
| `app.snapshot` | current high-level screen and connection state |
| `navigation.focusChanged` | semantic focus title/kind, not SwiftUI identity |
| `playback.snapshot` | sanitized player state |
| `capabilities.changed` | current command availability |
| `session.error` | stable redacted error code |
| `session.revoked` | device credential was revoked |

Playback snapshots follow
[`specs/common/playback.schema.json`](../../specs/common/playback.schema.json).
They exclude the playback URL and provider IDs. Artwork is served through an
authenticated Mac-owned endpoint or embedded bounded payload, never by handing
the Remote a provider credential or tokenized URL.

## 8. State synchronization

- Mac sends a full snapshot after authentication and reconnect.
- Subsequent events may be incremental, but Remote can request a full snapshot.
- Snapshot revisions are monotonic per Mac runtime. Remote ignores stale
  revisions.
- Commands are serialized at the Mac semantic-command boundary.
- Connection loss never changes playback by itself.
- Remote UI clearly distinguishes disconnected, connecting, paired, and revoked
  states.

## 9. Error model

Wire errors contain stable codes and optional safe context:

```text
unsupportedProtocol
unsupportedCapability
unauthenticated
revoked
invalidMessage
staleSequence
invalidState
rateLimited
internal
```

No raw Swift errors, provider response bodies, URLs, headers, or file paths are
serialized.

## 10. Shared conformance

Swift and Dart implementations must execute the same sanitized vectors for:

- envelope validation and unknown optional fields
- capability negotiation
- playback snapshots and finite-second validation
- duplicate/stale sequence handling
- command acknowledgement versus state update
- redacted errors
- reconnect/full snapshot behavior

Transport integration tests additionally cover Bonjour, pinned TLS, pairing
expiry, device revocation, sleep/wake, network switching, and background/return.

## 11. Open design items

- TLS identity creation, rotation, and migration
- exact device credential format
- WebSocket subprotocol identifier
- snapshot/event payload schemas beyond playback state
- artwork transfer/cache policy
- mobile background and notification scope
- mDNS and certificate-pinning implementation packages for Flutter

These remain open until the Phase 0 interoperability/security spike. Boundary
and privacy rules above are not open.
