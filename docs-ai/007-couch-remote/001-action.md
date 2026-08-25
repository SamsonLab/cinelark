# 007 — Couch Remote: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-25 | Narrowed the mobile milestone to a couch Remote without provider access or local playback | [Plan](000-plan.md) |
| 2026-08-25 | Defined version-1 pairing, command, snapshot, and authentication contracts | [`remote-protocol.md`](../../docs/interfaces/remote-protocol.md) |
| 2026-08-25 | Added a separate Rust TLS/WebSocket Remote gateway and kept Mac semantic authorization authoritative | [ADR-0008](../../docs/decisions/0008-rust-remote-transport.md) |
| 2026-08-25 | Added Mac pairing/revocation UI, semantic navigation, revisioned search input, login routing, and playback snapshots | Working tree |
| 2026-08-25 | Extended the IINA bridge/plugin for fullscreen, subtitle disable, track snapshots, and Remote-driven player state | Working tree |
| 2026-08-25 | Added the Flutter iOS/Android Remote with pairing, reconnect, login, navigation, search, and contextual playback controls | [`apps/remote`](../../apps/remote) |
| 2026-08-25 | Hardened one-time pairing, capability authorization, bounded queues/connections, stable errors, TLS identity coding, and child shutdown | Working tree |
| 2026-08-25 | Added ordered Mac broadcasts, helper-crash failure state, graceful helper shutdown, and a physical-device release checklist | [`apps/remote/README.md`](../../apps/remote/README.md) |
| 2026-08-25 | Fixed real-device pairing: toolbar entry, retryable same-code scanning, numeric LAN address, framed `i64` expiry, TLS 1.2, and generation-scoped helper callbacks | Working tree |
| 2026-08-25 | Removed the retry-time camera start race by letting the remounted scanner own auto-start | Working tree |
| 2026-08-25 | Diagnosed full-device VPN interception and routed Android WSS sockets through the active non-VPN Wi-Fi `Network` with native certificate pinning | Working tree |

## Outcome & current state (as of 2026-08-25)

CineLark now has a focused Flutter couch Remote for iOS and Android. The phone
scans a five-minute QR payload, pins the Mac gateway certificate, waits for
explicit Mac approval, and stores only its device-scoped credential in platform
secure storage. Reconnect uses a connection-bound HMAC proof; revoked or unknown
credentials return the phone to pairing.

The bundled `CineLarkRemoteGateway` Rust child owns only LAN WSS, TLS identity,
pairing-secret consumption, device proof verification, exact sequence checks,
message/rate/connection bounds, stable error redaction, and framed parent stdio.
The Mac owns paired-device records, capability grants, command authorization,
provider login, navigation/focus, text sessions, playback continuity, and every
IINA operation. It remains fully usable without the Remote.

The Flutter UI switches context between remote login, semantic browsing/search,
and now playing. Playback controls include pause/resume, relative and absolute
seek, scrub reconciliation, speed, volume/mute, fullscreen, previous/next
episode, audio/subtitle selection including subtitle disable, and player close
with CineLark activation. Previous/next remains a Mac episode-continuity
operation rather than an IINA playlist command.

Shared schemas and sanitized fixtures live under `specs/remote/` and
`fixtures/conformance/`. The Remote gateway and IINA bridge remain separate
executables, ports, credentials, and failure domains.

## Validation

- `cargo test` passed 14 Remote gateway tests, including framed pairing expiry and TLS 1.2 WSS; `cargo clippy --all-targets -D warnings` passed.
- `cargo test` passed 11 IINA bridge tests; `cargo clippy --all-targets -D warnings` passed.
- `swift test --package-path packages/apple/CineLarkKit` passed 41 tests.
- The macOS Xcode test action passed 10 tests, including episode navigation,
  Remote text revisions, and numeric LAN address selection.
- `npm test --prefix plugins/iina` passed 23 tests.
- Contract validation passed all 6 sanitized fixtures.
- `flutter analyze` passed and `flutter test` passed 6 protocol, scan-gate, and
  scanner-remount tests.
- Flutter produced an iOS Simulator app and an Android debug APK.
- A physical Android 10 device reached the QR's numeric Mac endpoint and
  received HTTP 200 from the gateway over TLS 1.2.
- A framed child-process smoke test observed `identityGenerated`, `ready`, and clean gateway exit with no orphan process.

## Deviations from plan

- Flutter version 1 reconnects to the QR endpoint rather than browsing Bonjour.
  The Mac advertises `_cinelark._tcp`; Bonjour endpoint recovery remains
  additive work for host or port changes.
- The initial Flutter structure stays application-local and deliberately small
  instead of introducing multiple Dart packages before a second consumer
  exists.
- `flutter_secure_storage` remains on the 10.x line because its 11.x Android
  compile-SDK requirement is ahead of the repository's working Flutter/Android
  toolchain. Android backup is disabled and iOS Keychain entitlements are
  explicit.
- Automated platform builds replace the planned physical-device integration
  suite for this implementation pass.

## Open questions

- Run the complete pairing, background/resume, network-switch, revocation, and
  every-player-control matrix on physical iOS and Android devices against a
  signed Mac build and a declared compatible stock-IINA version.
- Add Bonjour endpoint recovery without weakening certificate pinning or device
  authentication.
- Decide whether lock-screen controls and authenticated artwork materially
  improve the focused couch workflow before expanding the Remote scope.
