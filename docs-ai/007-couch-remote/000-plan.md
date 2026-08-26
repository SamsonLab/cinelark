# 007 — Couch Remote: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-25 |
| **Primary refs** | [Action log](001-action.md) |
| **Related** | [`docs/interfaces/remote-protocol.md`](../../docs/interfaces/remote-protocol.md), [`docs/decisions/0002-native-macos-flutter-remote.md`](../../docs/decisions/0002-native-macos-flutter-remote.md), [`docs/interfaces/playback-bridge.md`](../../docs/interfaces/playback-bridge.md) |

## Background

CineLark is operated from a couch while the Mac is connected to a television.
The first mobile product is therefore a focused iOS/Android Remote rather than
an independent media client. It must cover the complete path from signed-out
Mac state through browsing, search text entry, and advanced IINA playback
control without giving the phone provider authority or playback URLs.

The current repository has a semantic keyboard-navigation coordinator, an
IINA-facing Rust broker, a Swift playback coordinator, and draft Remote wire
rules. It has no Flutter application, Mac RemoteGateway, LAN listener, pairing
UI, or cross-runtime Remote implementation.

## Goals

1. Add a Flutter Remote application for iOS and Android with QR pairing,
   reconnect, revocation handling, and contextual login/navigation/text/player
   surfaces.
2. Keep the Mac authoritative for provider credentials, navigation/focus,
   playback descriptors, episode continuity, and progress synchronization.
3. Provide remote credential submission for username/password/optional TOTP
   without persistence or diagnostic leakage on the phone, Mac, or helper.
4. Route local keyboard and Remote navigation through one semantic dispatcher,
   including directional movement, activation, back, and direct sidebar
   selection.
5. Add revisioned remote text-input sessions for search with commit, cancel,
   reconnect, and stale-session rejection.
6. Expose playback snapshots and commands for pause/resume/stop, seeking,
   playback speed, fullscreen, previous/next episode, audio/subtitle selection,
   and atomic player close plus CineLark activation.
7. Scope every playback command to a playback ID, and snapshot-sensitive track
   and episode commands to a monotonic revision, so replacement playback and
   stale option lists cannot accept commands.
8. Implement shared JSON Schemas and sanitized conformance fixtures exercised
   by Rust, Swift, and Dart.
9. Validate pairing, authentication, sequence/revision handling, reconnect,
   sleep/wake recovery, and IINA command mapping with automated tests and a
   documented manual device checklist.

### Non-goals

- A standalone mobile media-library client.
- Provider API access or persistent provider credentials on the phone.
- Local mobile playback, an embedded CineLark decoder, AirPlay, or Google Cast.
- Internet-routed Remote sessions; the initial transport is local-network only.
- Replacing IINA/mpv or changing the existing sequential replacement policy.
- Exposing provider DTOs, bridge secrets, playback URLs, or filesystem paths.

## Design / Approach

### Ownership and processes

- `CineLark.app` owns all product state and authorizes every semantic command.
- A supervised Rust child process owns the LAN TLS/WebSocket transport,
  connection framing, size/rate limits, and sequencing.
- The Rust process forwards authenticated Remote messages to the Mac over
  private framed stdio and cannot perform provider or navigation operations.
- The Flutter application owns only paired-device material, transient input,
  presentation state, and protocol/session recovery.

The existing Rust helper will be evolved behind explicit service boundaries;
Remote transport must not weaken the loopback-only IINA endpoint or reuse the
IINA pairing secret.

### Pairing and session security

- The Mac creates an expiring single-use pairing request and displays a QR code
  containing an endpoint hint, service ID, protocol version, certificate
  fingerprint, and high-entropy secret.
- The Flutter client pins the advertised TLS certificate before submitting the
  one-time secret.
- The Mac requires explicit approval and then issues a device-scoped credential
  that can be individually revoked.
- Credentials are stored in Keychain/Keystore. Pairing material and remote login
  credentials are erased after use and are always structurally redacted.
- Capabilities, not implementation versions, gate commands.

### Mac semantic surfaces

- Extract a semantic command dispatcher from `ShortcutCoordinator`; `NSEvent`
  and `RemoteGateway` become peer adapters.
- Model login as a dedicated sensitive request, not generic keystroke injection.
- Model search as a revisioned text-input session owned by the focused Mac view.
- Publish additive app, input, and playback snapshots. A playing session may
  coexist with browsing or text input.

### Playback control

- Extend the provider-neutral playback command/event layer before adding
  backend-specific behavior.
- Previous/next episode is handled by `PlaybackCoordinator`; it is not an IINA
  playlist command.
- `closeAndActivateApp` is one Mac semantic operation: finalize playback, close
  the managed player, and activate CineLark after the close acknowledgement or
  bounded timeout.
- Scrubbing previews locally on the phone and commits a bounded absolute seek;
  telemetry is reconciled after the resulting snapshot revision.
- Track IDs are valid only inside one playback ID.

### Flutter structure

- Keep transport, secure storage, QR scanning, protocol, and feature state in
  separate packages/layers with injectable interfaces.
- Present contextual surfaces for connection/pairing, login, navigation, text
  input, and now-playing rather than mirroring SwiftUI view identities.
- Use widget tests for reducers/controllers and golden tests only after behavior
  stabilizes. Platform integration tests cover local-network permissions,
  Keychain/Keystore, camera scanning, and lifecycle reconnect.

### Delivery slices

1. Protocol schemas, conformance fixtures, Rust transport state machine, and
   fake-host integration tests.
2. Mac pairing UI, gateway supervision, semantic navigation, and Flutter
   pairing/navigation client.
3. Search text-input sessions and dedicated remote login.
4. Basic now-playing snapshots and transport controls.
5. Fullscreen, rate, scrubbing, track selection, episode navigation, and
   close/focus restoration.
6. Sleep/wake, network switching, revocation, packaging, and device validation.

Each slice must be end-to-end; no platform may accumulate an unconsumed private
contract as a substitute for working behavior.

## Alternatives & decisions

- **Independent Flutter client now:** rejected because it duplicates provider
  and product state before local playback exists and delays the couch-control
  outcome.
- **Remote sends raw key events:** rejected because view focus, keyboard layout,
  and modal behavior are unstable wire contracts.
- **Remote talks directly to IINA:** rejected because it bypasses Mac session
  ordering, progress synchronization, and credential boundaries.
- **Cleartext LAN WebSocket after QR pairing:** rejected because credentials and
  now-playing state require confidentiality and pinned endpoint identity.
- **Mac-only networking implementation:** rejected for the initial direction;
  Rust already provides a supervised broker boundary and gives a portable,
  testable transport core. The Mac remains the authorization authority.
- **One message enum containing credentials and ordinary diagnostics:** rejected;
  sensitive messages require structural redaction and a deliberately narrow
  lifecycle.

## Amendments

- High-frequency transport, seek, and volume commands are scoped by playback ID
  but not snapshot revision. Requiring the rapidly changing telemetry revision
  would reject valid couch input without adding replacement-session safety.
- Updated 2026-08-26: The mobile client now persists multiple named Mac
  pairings and starts at an explicit device-selection surface; see
  [002-multi-device-selection.md](002-multi-device-selection.md).
- Updated 2026-08-26: Device presentation uses host names without CineLark
  branding and explicit host-platform metadata; see
  [003-host-identity-presentation.md](003-host-identity-presentation.md).
