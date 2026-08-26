# ADR-0008: Rust Remote transport with Mac authorization

- **Status:** Superseded in part by [ADR-0009](0009-unified-native-gateway.md)
- **Date:** 2026-08-25
- **Related:** [ADR-0002](0002-native-macos-flutter-remote.md), [Remote protocol](../interfaces/remote-protocol.md)

## Context

CineLark Remote needs a pinned TLS WebSocket server, bounded message framing,
pairing expiry, device authentication, sequencing, rate limits, and reliable
sleep/wake restart behavior. The Mac app must remain authoritative for account,
navigation, focus, playback, progress, and device approval.

The existing Rust playback helper demonstrates the desired supervised-child and
private-stdio boundary, but its IINA endpoint is loopback-only and authenticated
with an unrelated plugin secret. Combining LAN Remote traffic with that endpoint
would couple two trust domains and make playback-helper failure affect Remote
availability.

## Decision

1. Add a separate bundled Rust executable, `CineLarkRemoteGateway`, supervised
   by the Mac app from application startup.
2. The gateway owns only Remote transport concerns:
   - TLS identity loading/generation and certificate fingerprinting
   - LAN WebSocket listening
   - frame and payload limits
   - pairing-secret expiry
   - device credential proof verification
   - per-connection sequence and rate enforcement
   - forwarding authenticated envelopes over private framed stdio
3. The Mac app owns and persists Remote identity and paired-device records,
   starts/stops pairing, approves/rejects requests, grants capabilities, and
   interprets all semantic commands.
4. `CineLarkRemoteGateway` and `CineLarkBridge` use separate processes, ports,
   secrets, protocols, and failure domains. Remote never reaches the IINA helper
   directly.
5. The Mac may request a gateway-generated self-signed identity on first launch,
   then stores its private material in Keychain and supplies it on later starts.
6. Flutter pins the certificate fingerprint encoded in the QR payload. There is
   no cleartext fallback and no trust-on-first-use outside an explicit pairing
   session.
7. Remote login credentials are opaque sensitive payloads to the gateway. They
   are forwarded only after device authentication, never persisted, and always
   structurally redacted from diagnostics.

## Consequences

### Positive

- TLS and WebSocket behavior is testable without SwiftUI or a physical phone.
- The transport core is reusable by a future Windows host.
- Mac product state remains isolated from untrusted LAN parsing.
- IINA bridge availability and Remote availability have independent lifecycles.
- Pairing and device authorization remain visible and revocable in the Mac UI.

### Costs

- The app supervises and signs a second Rust executable.
- Private framed stdio needs a typed request/reply protocol and liveness policy.
- TLS identity material crosses the private parent/child boundary in memory.
- Bonjour advertisement and QR presentation still require Mac integration.

## Rejected alternatives

- **Host WSS entirely in Swift:** duplicates framing, rate limiting, and portable
  transport work while making deterministic integration testing harder.
- **Extend the IINA helper with a LAN listener:** couples unrelated trust and
  liveness domains and risks exposing the loopback playback broker.
- **Let Rust authorize semantic commands:** moves account/navigation/playback
  authority out of the application layer and duplicates Mac state.
- **Use cleartext WebSocket plus an application HMAC:** leaks private state and
  recreates incomplete transport security.
- **Let Remote connect directly to IINA:** bypasses playback ordering, progress
  synchronization, redaction, and Mac device revocation.

## Revisit when

Revisit only if the separate helper creates measured packaging or lifecycle
failures that cannot be fixed without merging processes. Do not weaken TLS,
pinning, or Mac authorization to remove the helper boundary.

The 0.1.9 package-size increase satisfied this condition. ADR-0009 merges the
executable and runtime while preserving the TLS, pinning, authorization,
protocol, credential, port, and center-state boundaries defined here.
