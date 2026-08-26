# ADR-0009: Unified native gateway process with independent centers

- **Status:** Accepted
- **Date:** 2026-08-26
- **Supersedes:** [ADR-0008](0008-rust-remote-transport.md) only where it requires separate executables and failure domains
- **Related:** [ADR-0003](0003-bundled-rust-bridge-helper.md), [Playback bridge](../interfaces/playback-bridge.md), [Remote protocol](../interfaces/remote-protocol.md)

## Context

CineLark 0.1.9 bundled separate universal Rust executables for the IINA bridge
and Remote transport. Their duplicated Tokio, Axum, and cryptographic runtime
cost increased the compressed release from about 10.3 MB to 17.0 MB. The two
helpers occupied about 17.3 MiB before compression.

Process isolation protected the two trust domains, but that protection can be
preserved at explicit protocol, listener, credential, and state-machine
boundaries. The measured packaging cost satisfies ADR-0008's revisit condition.

## Decision

1. Bundle one supervised `CineLarkGateway` child executable.
2. Keep two explicit centers in Rust and Swift:
   - `IINABridgeCenter` owns only authenticated loopback HTTP, the plugin secret,
     IINA command ordering, and player events.
   - `RemoteGatewayCenter` owns only LAN TLS/WSS, identity, pairing, device
     credentials, sequencing, and rate enforcement.
3. Share only the process shell, Tokio runtime, framed parent stdio, and linked
   runtime dependencies.
4. Namespace every parent frame as `iina`, `remote`, or `process`. Center-scoped
   shutdown and recoverable errors do not stop or reconfigure the other center.
5. Keep ports, secrets, wire protocols, authorization state, and network binding
   rules separate. Remote never reaches IINA directly.
6. The Swift composition root creates one process supervisor and injects the two
   typed center transports into their existing feature coordinators.
7. Process termination necessarily clears both centers' readiness. Each feature
   coordinator retains its own recovery and user-visible failure behavior.

## Consequences

- The app signs, packages, and supervises one helper instead of two.
- Linked Rust networking and crypto dependencies are stored once.
- Code-level trust boundaries remain reviewable and independently testable.
- A process crash affects both transports even though recoverable center failures
  remain isolated. This is the accepted cost of removing duplicate binaries.
- The IINA plugin continues to use outbound authenticated HTTP long-polling;
  this decision does not make stock IINA's inbound WebSocket server acceptable.
