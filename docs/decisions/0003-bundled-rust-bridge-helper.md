# ADR-0003: Bundled Rust helper for the IINA bridge

- **Status:** Implemented; signed distribution validation required
- **Date:** 2026-08-20

## Context

The IINA plugin can control playback and issue outbound HTTP requests. Its
WebSocket server, however, cannot bind to loopback, has no TLS, enables
peer-to-peer networking, and exposes no JavaScript stop operation. Requiring
users to install a runtime, configure ports, or manage a daemon would undermine
CineLark's product goals.

## Decision

1. Implement the bridge broker as a self-contained Rust executable bundled and
   signed inside CineLark.app.
2. Launch it on demand as a supervised child process; communicate with the Mac
   app through framed JSON on stdin/stdout.
3. Bind the plugin-facing endpoint explicitly to IPv4/IPv6 loopback and use
   authenticated bounded HTTP long-poll/event POST traffic.
4. Keep the IINA JavaScript/TypeScript plugin minimal and provider-neutral.
5. Require no Cargo/Rust runtime, Homebrew package, launch agent, admin access,
   manual port, or separately managed service on user machines.
6. Bundle the matching plugin artifact and expose a guided official IINA
   install/update action from CineLark.
7. Retain direct-open playback as a degraded first-stage adapter while the
   bridge is unavailable; browsing and provider login remain functional.

## Consequences

- Rust owns protocol validation, ordering, limits, and process isolation.
- The IINA plugin uses a smaller attack surface and no inbound listener.
- The app release must build, combine, sign, notarize, update, and supervise a
  universal helper binary.
- HTTP long-poll, plugin scheduling, dual-loopback binding, authenticated
  process framing, and replacement playback have automated coverage.
- Pairing uses the reviewed high-entropy Keychain/HMAC flow in
  [ADR-0004](0004-iina-bridge-pairing.md). Signed stock-IINA behavior remains a
  release validation gate.

## Fallback

If outbound HTTP cannot satisfy measured latency/lifecycle requirements, prefer
a minimal upstream IINA WebSocket-client or local IPC capability. Do not default
to the current all-interface WebSocket listener or a persistent user-managed
daemon.
