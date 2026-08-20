# Technical Implementation Plan

- **Status:** Draft
- **Last updated:** 2026-08-20
- **Platform decision:** [ADR-0002](decisions/0002-native-macos-flutter-remote.md)

## 1. Guiding decisions

- macOS is Apple-native: Swift 6, SwiftUI first, AppKit when justified by a
  concrete platform gap.
- Remote is Flutter/Dart and targets iOS and Android.
- The IINA bridge uses a bundled Rust helper plus a minimal JavaScript plugin;
  users never install a Rust runtime or configure a daemon.
- The Mac app is the authority for provider, navigation, playback, and pairing
  state.
- Shared contracts are designed before cross-runtime features. Do not attempt
  to share UI or provider implementation code between Swift and Dart.
- IINA/mpv remains the playback engine; CineLark does not implement decoding.

## 2. macOS stack

| Concern | Default |
| --- | --- |
| Language | Swift 6 with strict concurrency |
| UI | SwiftUI and Observation |
| Platform escape hatch | focused AppKit adapters |
| Concurrency | async/await, task groups, actors, cancellation |
| Networking | `URLSession` with typed `Codable` DTOs |
| Secrets | Security/Keychain wrapper |
| Logging | `Logger`/OSLog with privacy-safe values |
| Modules | Swift Package Manager local package, multiple targets |
| Unit tests | Swift Testing; XCTest where platform/UI tooling requires it |
| UI tests | XCUITest plus focused state-machine tests |

The minimum macOS/Xcode/IINA versions remain open until two spikes validate
SwiftUI focus behavior and the stock-IINA bridge.

### 2.1 Swift package graph

Start with one local package to avoid package-management overhead while keeping
compile-time boundaries:

```text
apps/macos/CineLarkApp
  ├── CineLarkFeatures
  ├── CineLarkDesignSystem
  └── composition root
          │
          ▼
packages/apple/CineLarkKit
  ├── CineLarkApplication ──▶ CineLarkDomain
  ├── CineLarkUHDNow ───────▶ CineLarkDomain
  ├── CineLarkBridgeClient ──▶ CineLarkDomain
  ├── CineLarkRemoteGateway ─▶ CineLarkApplication
  ├── CineLarkPersistence ──▶ CineLarkDomain
  ├── CineLarkDesignSystem
  └── CineLarkTestSupport
```

Target rules:

- `CineLarkDomain` imports Foundation only when its value semantics require it;
  it does not import SwiftUI, AppKit, provider DTOs, or IINA types.
- `CineLarkApplication` owns use cases and state machines but no concrete
  networking or storage.
- Adapter targets translate external contracts at the boundary.
- The app target is the composition root and the only place that chooses
  concrete implementations.
- Split the local package only after measured ownership/build-time pressure.

### 2.2 UI and focus architecture

- Feature models are `@MainActor` and use the Observation framework.
- Views render state and emit semantic actions; they do not start provider or
  bridge requests directly.
- Directional navigation uses stable logical `FocusID` values and an explicit
  navigation graph. SwiftUI `FocusState` reflects that graph rather than being
  the sole source of truth.
- Keyboard, media key, game controller, and future Remote inputs map into one
  command vocabulary: move, select, back, menu, play/pause, seek, and volume.
- AppKit adapters are acceptable for event monitoring, first-responder/window
  control, and focus behavior that cannot be made deterministic in SwiftUI.
- Poster/image completion must not change logical focus identity.

This separation makes focus behavior unit-testable and lets Remote commands
reuse semantics without exposing SwiftUI implementation details.

### 2.3 State and services

Use explicit actors for mutable I/O state:

- `ProviderSessionActor` — token lifecycle and authenticated requests
- `ImagePipelineActor` — request deduplication and bounded caches
- `PlaybackSessionActor` — Rust helper process, bridge connection, and session ordering
- `ProgressReporterActor` — coalescing, monotonic ordering, and retries
- `RemoteGatewayActor` — paired devices, sessions, and sanitized broadcasts

Do not add a database initially. Start with Keychain for secrets and bounded
file caches for recreatable data. Introduce SQLite/GRDB only when offline state,
querying, or migration requirements are demonstrated.

### 2.4 Dependencies

Prefer Apple frameworks and small protocol seams first. Add a third-party
library only after the responsible adapter has tests and the dependency reduces
real lifecycle/security complexity. In particular:

- evaluate an established image pipeline instead of growing a large custom one;
- do not add a general architecture framework before feature state machines
  demonstrate the need;
- isolate Keychain, database, and networking dependencies behind CineLark
  protocols.

## 3. Flutter Remote stack

| Concern | Default |
| --- | --- |
| Framework | current stable Flutter |
| Language | Dart 3 |
| Targets | iOS and Android |
| State | Riverpod, isolated behind feature/application boundaries |
| Navigation | `go_router` if multiple product flows justify it |
| Serialization | generated contract models plus conformance tests |
| Secrets | Keychain/Keystore through a narrow secure-storage adapter |
| Tests | Dart unit, Flutter widget/golden, and device integration tests |

Proposed structure:

```text
apps/remote/
  lib/
    app/                 composition, routing, theme
    application/         connection and command use cases
    features/            pairing, remote, now playing, settings
    protocol/            generated models and mapping adapters
    infrastructure/      discovery, TLS transport, secure storage
  test/
  integration_test/
```

Rules:

- No UHDNow/provider DTO or credential enters the Flutter project.
- UI state is derived from sanitized Mac snapshots and local connection state.
- Bonjour, certificate pinning, and background lifecycle APIs remain behind
  interfaces; use a platform channel only if maintained Flutter packages cannot
  meet the security/behavior requirements.
- The Remote must tolerate capability differences and protocol version ranges;
  it must not infer support from app version strings.

## 4. Rust bridge helper

### 4.1 Process topology

The preferred bridge avoids asking IINA's JavaScript WebSocket API to accept
inbound network connections:

```text
CineLark for Mac
  │ private child-process stdin/stdout
  ▼
CineLarkBridge (bundled Rust executable)
  │ authenticated HTTP/long-poll on 127.0.0.1 and ::1 only
  ▼
CineLark IINA Plugin (minimal JavaScript/TypeScript)
  │ IINA public plugin API
  ▼
IINA / mpv
```

The Mac app launches the helper on demand with `Process`, supervises it, and
terminates it with the app/session. App-to-helper traffic uses framed JSON over
child stdio, so it requires no second listening socket. The helper owns the
loopback listener used by the IINA plugin.

### 4.2 Rust defaults

| Concern | Default |
| --- | --- |
| Toolchain | pinned stable Rust with an explicit MSRV |
| Runtime | self-contained native helper; no user-installed Rust runtime |
| Async/HTTP | Tokio + Axum candidate, accepted only after size/latency spike |
| Serialization | Serde/`serde_json` against shared conformance vectors |
| Logging | `tracing` with mandatory structured redaction |
| Supply chain | locked dependencies, `cargo audit`, `cargo deny` |
| Distribution | signed universal macOS helper embedded in CineLark.app |

Build arm64 and x86_64 artifacts in CI, combine/sign them as part of the app
bundle, and verify the nested code signature. The helper has no provider client,
UI, updater, launch agent, or persistent background mode.

### 4.3 Plugin-facing local API

Candidate endpoints are internal and versioned:

```text
GET  /v1/health
POST /v1/plugin/hello
GET  /v1/plugin/commands?after=<sequence>
POST /v1/plugin/events
```

- Bind explicitly to loopback; never wildcard interfaces.
- Select automatically from a small reserved port range and let the plugin
  probe it, so users never configure a port.
- Keep health responses non-sensitive.
- Authenticate plugin traffic before accepting commands/events.
- Use bounded long-polling rather than high-frequency polling.
- Apply request size, timeout, connection, and rate limits.

IINA's audited `http` API can make outbound requests to allowed hosts and is the
only plugin networking capability needed by this design. The plugin manifest
allowlist should contain only `127.0.0.1` and `::1` when host validation permits
both forms.

### 4.4 Pairing and lifecycle

On first connection, the helper forwards a pairing request to the Mac app. The
user approves the detected CineLark plugin once; the plugin stores a random,
revocable bridge credential in its IINA-scoped Keychain. Subsequent sessions
authenticate automatically.

Exact credential provisioning and message authentication remain part of
`BRIDGE-SEC-001`. Pairing must not require copying configuration files, editing
IINA preferences, or entering account credentials twice.

### 4.5 Zero-configuration delivery

- Bundle the Rust helper inside CineLark.app; no Homebrew, Cargo, shell, admin,
  login item, or separate installer.
- Bundle the matching `.iinaplgz` artifact and drive IINA's official install
  flow from an in-app **Install/Update Bridge** action.
- Detect IINA, plugin, helper, and protocol versions automatically.
- Start/stop the helper on demand and reconnect after IINA restarts.
- Offer clear one-action remediation and a degraded direct-open mode if the
  plugin is unavailable, without blocking library browsing.

### 4.6 Required spike

Before freezing this topology, prove:

1. IINA `http` requests to both loopback families work with its domain allowlist.
2. Bounded long-poll does not block the plugin queue or degrade playback.
3. Command/event latency is acceptable for pause, seek, and position updates.
4. Port discovery, helper crash recovery, sleep/wake, and multiple IINA windows
   are deterministic.
5. Pairing resists unauthorized local clients within the documented threat
   model.
6. Universal binary size, signing, notarization, and update replacement work
   without user steps.

If the spike fails, prefer a small upstream IINA IPC/WebSocket-client capability
over exposing the current all-interface, no-TLS WebSocket server or requiring a
persistent user-managed daemon.

## 5. Shared-first design

### 5.1 What is shared

| Artifact | Source of truth | Consumers |
| --- | --- | --- |
| Playback state and track semantics | `specs/common/` | Swift, Rust, Dart, plugin |
| App ↔ IINA envelope/messages | `specs/bridge/` | Swift, Rust, TypeScript/JavaScript |
| Remote ↔ Mac envelope/messages | `specs/remote/` | Swift, Dart |
| Provider observation | `specs/uhdnow/` | Swift provider adapter |
| Compatibility fixtures | `fixtures/conformance/` | all protocol runtimes |
| Color/type/spacing tokens | `shared/design/` | SwiftUI, Flutter |
| Source logo/icon vectors | `shared/brand/` | all applications/plugins |

### 5.2 What is not shared

- SwiftUI/AppKit and Flutter widgets
- provider DTOs or networking clients
- Keychain/Keystore implementations
- Bonjour and TLS platform adapters
- process/window lifecycle code
- cache/database implementations

### 5.3 Contract workflow

1. Change schema and compatibility notes first.
2. Add sanitized positive and negative conformance vectors.
3. Generate or update Swift/Rust/Dart/TypeScript representations.
4. Run every affected runtime's decoder/encoder tests.
5. Land consumers atomically in the monorepo.

Generated code carries a header naming its source schema and generator version
and is never edited by hand. Code generation is adopted only after a spike
confirms stable Swift and Dart output; until then, handwritten models must pass
the same vectors.

### 5.4 Compatibility rules

- Envelopes carry a protocol major version and capability set.
- Additive optional fields are backward compatible.
- Renames, removals, unit changes, and semantic changes require a major version.
- Unknown optional fields are ignored; unknown required capabilities fail
  negotiation explicitly.
- IDs are opaque UUID/string values. Playback time is finite seconds at all
  internal wire boundaries.
- Provider units such as UHDNow ticks never appear in shared protocols.

## 6. Remote discovery and security

The recommended design is documented in
[`interfaces/remote-protocol.md`](interfaces/remote-protocol.md):

- Bonjour advertises service identity and protocol range, never secrets.
- Remote transport is WebSocket over TLS.
- Pairing uses a high-entropy one-time QR payload and certificate pinning.
- Successful pairing issues a device-scoped revocable credential.
- Remote snapshots exclude provider tokens, playback URLs, and provider DTOs.

This is separate from the IINA Bridge transport and does not inherit its
no-TLS/all-interface limitations.

## 7. CI and release topology

Path-scoped jobs:

```text
specs     schema lint, link/security checks, conformance vectors
macos     Swift format/lint, package tests, app build, UI tests
rust      fmt, clippy, test, audit/deny, universal helper build
remote    Dart analyze/test, Flutter widget/integration builds
plugin    typecheck/lint/test/package, bridge conformance
```

Suggested independent tags:

```text
app-v0.1.0
remote-v0.1.0
iina-plugin-v0.1.0
```

A shared protocol compatibility matrix is published with each release.

## 8. Implementation phases

### Phase 0 — de-risk foundations

1. Prototype deterministic SwiftUI focus with keyboard/remote input and an
   AppKit fallback.
2. Validate the bundled Rust helper and outbound IINA HTTP/long-poll topology,
   including `BRIDGE-SEC-001`.
3. Validate JSON Schema generation/validation in Swift, Rust, Dart, and
   TypeScript.
4. Prototype Flutter Bonjour discovery, pinned WSS, secure storage, and local
   network permission flows on both iOS and Android.

### Phase 1 — native vertical slice

- Create the Swift package/module graph and app shell.
- Implement a synthetic `MediaLibraryProvider`.
- Build one home row, detail page, focus restoration, and fake playback flow.
- Establish design tokens and snapshot/focus tests.

### Phase 2 — UHDNow integration

- Implement authentication, DTO mapping, collections/search/details/assets.
- Add Keychain session restoration and complete redaction tests.
- Add resume/progress behavior against sanitized contract fixtures.

### Phase 3 — IINA playback

- Implement, embed, sign, and supervise the Rust bridge helper.
- Implement and package the provider-neutral thin IINA plugin.
- Complete play/resume/state/track/progress integration.
- Add stock-IINA compatibility tests and failure UX.

### Phase 4 — macOS MVP hardening

- Complete TV-first surfaces and deterministic focus coverage.
- Measure launch, image, memory, and navigation budgets.
- Finalize signing, updates, and minimum platform versions.

### Phase 5 — Flutter Remote

- Freeze Remote protocol version 1 after the Phase 0 spike.
- Implement pairing, discovery, reconnect, now playing, navigation, transport,
  volume, device management, and revocation.
- Validate iOS and Android lifecycle/background behavior.

## 9. Decisions intentionally left open

- Minimum OS and toolchain versions
- Swift/Rust/Dart/TypeScript schema generator
- Rust MSRV and final minimal HTTP/async dependency set
- Image pipeline and persistence dependencies
- Whether the IINA bridge needs an upstream IINA API change
- Remote TLS identity rotation and migration details
- Flutter packages for mDNS, secure storage, and certificate pinning

These decisions require measured spikes; they do not block the module and
contract boundaries above.
