# 009 — Unified Native Gateway: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-26 |
| **Primary refs** | [`001-action.md`](001-action.md), `docs/decisions/0009-unified-native-gateway.md`, `packages/rust/cinelark-gateway`, `packages/apple/CineLarkKit/Sources/CineLarkGateway` |
| **Related** | [`007`](../007-couch-remote/000-plan.md), [`008`](../008-safe-iina-plugin-lifecycle/000-plan.md), [ADR-0003](../../docs/decisions/0003-bundled-rust-bridge-helper.md), [ADR-0008](../../docs/decisions/0008-rust-remote-transport.md) |

## Background

CineLark 0.1.9 bundles `CineLarkBridge` for the loopback IINA integration and
`CineLarkRemoteGateway` for the LAN Remote transport. Both executables embed a
Tokio/Axum networking stack. The Remote helper increased the compressed release
artifact from about 10.3 MB to 17.0 MB, while the two universal helper binaries
occupy about 17.3 MiB before compression.

The separate processes protect distinct trust domains, but process separation
is not required to preserve the protocol, credential, listener, and state-machine
boundaries. One supervised executable can share the Rust runtime and linked
dependencies while retaining independent centers in both Rust and Swift.

## Goals

- Bundle one universal `CineLarkGateway` executable instead of two helpers.
- Keep `IINABridgeCenter` and `RemoteGatewayCenter` as explicit independent
  code-level centers with separate lifecycle and readiness state.
- Share only the process shell, Tokio runtime, framed parent IPC, and linked
  runtime dependencies.
- Preserve the existing loopback-only authenticated IINA HTTP protocol.
- Preserve the existing TLS-pinned Remote WebSocket protocol and Mac-owned
  authorization model.
- Allow either center to start, stop, fail, and restart without intentionally
  stopping the other center.
- Reduce signed app and compressed release size without changing user-visible
  playback or Remote behavior.

### Non-goals

- Replace IINA HTTP long-polling with WebSocket. Stock IINA does not expose a
  safe outbound WebSocket client, and its inbound server cannot meet CineLark's
  loopback and lifecycle requirements.
- Share secrets, authentication, ports, request schemas, or semantic authority
  between the two centers.
- Let Remote connect directly to IINA.
- Move Remote semantic command authorization into Rust.
- Introduce a persistent daemon, launch agent, or separately installed runtime.

## Design / Approach

### Rust process

Create one `cinelark-gateway` crate and executable. Its process shell owns:

- one Tokio runtime;
- one length-prefixed stdin reader and stdout writer;
- a namespaced parent envelope that routes frames to `iina`, `remote`, or
  `process`;
- process termination and unexpected-child-failure reporting.

`IINABridgeCenter` owns the loopback listeners, plugin secret, command queue,
event validation, and IINA readiness. `RemoteGatewayCenter` owns the LAN TLS
listener, identity, pairing expiry, device credentials, sequencing, and rate
limits. Neither center imports the other's protocol or state.

Recoverable center errors are emitted with their center namespace. A process
crash necessarily affects both centers; the Swift supervisor clears both
readiness states and allows normal coordinators to restart them.

### Swift process ownership

Add a `CineLarkGateway` package target containing one actor that supervises
`Contents/Helpers/CineLarkGateway`. It provides separate transport interfaces
to `CineLarkPlayback` and `CineLarkRemote`; the feature coordinators continue to
own their own state machines and consume only their respective typed events.

The application creates one supervisor and injects its IINA transport into
`ManagedIINAPlaybackLauncher` and its Remote transport into
`RemoteCoordinator`. Starting or stopping one transport sends a center-scoped
frame rather than terminating the shared process. Application termination sends
the process-scoped shutdown frame.

### Packaging and compatibility

Build, combine, sign, package, and verify only `CineLarkGateway`. The plugin's
loopback API and Remote client's WSS API remain wire-compatible, so this change
does not require a coordinated plugin or Flutter protocol migration.

## Alternatives & decisions

- **Keep two executables:** rejected after the measured 0.1.9 package-size
  increase showed duplicated linked runtime cost.
- **Merge both state machines:** rejected because it would couple unrelated
  credentials, trust domains, lifecycle, and protocol evolution.
- **Move both transports into Swift:** rejected because it discards the tested,
  portable Rust transport and duplicates framing and rate-limit behavior.
- **Switch IINA to WebSocket during the merge:** rejected because stock IINA's
  available WebSocket server cannot satisfy the required network boundary and
  lifecycle controls.
- **Run the helper for the entire login session:** rejected; CineLark continues
  to supervise an app-scoped child process with no persistent service.

## Validation

- Rust unit and integration tests cover namespaced routing and independent
  center lifecycle.
- Existing IINA broker and Remote gateway protocol tests pass against the
  unified executable.
- `swift test` passes for CineLarkKit, including supervisor and transport tests.
- The macOS Xcode test suite passes with the unified helper bundled.
- A release build contains exactly one executable in `Contents/Helpers` and
  passes architecture and code-sign verification.
- Record the old two-helper size, new one-helper size, and packaged artifact
  delta in `001-action.md`.
