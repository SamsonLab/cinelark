# Technical Implementation Plan

- **Status:** Implemented baseline; signed physical-device release gates remain
- **Last updated:** 2026-08-28
- **Platform decision:** [ADR-0002](decisions/0002-native-macos-flutter-remote.md)

## 1. Guiding decisions

- macOS is Apple-native: Swift 6, SwiftUI first, AppKit when justified by a
  concrete platform gap.
- Remote is Flutter/Dart and targets iOS and Android.
- The IINA bridge and Remote transport use independent centers inside one
  bundled Rust helper. IINA uses a minimal JavaScript plugin; Remote uses a
  pinned TLS/WebSocket endpoint. Users never install Rust or configure a
  daemon.
- The Mac app is the authority for provider, navigation, playback, and pairing
  state.
- Shared contracts are designed before cross-runtime features. Do not attempt
  to share UI or provider implementation code between Swift and Dart.
- IINA/mpv remains the playback engine; CineLark does not implement decoding.

## 2. macOS stack

| Concern | Default |
| --- | --- |
| Language | Swift 6 with strict concurrency |
| UI | SwiftUI; TCA 1.26.1 owns Feature/Application state |
| Platform escape hatch | focused AppKit adapters |
| Concurrency | async/await, task groups, actors, cancellation |
| Networking | `URLSession` with typed `Codable` DTOs |
| Secrets | Security/Keychain wrapper |
| Logging | `Logger`/OSLog with privacy-safe values |
| Modules | Swift Package Manager local package, multiple targets |
| Unit tests | Swift Testing; XCTest where platform/UI tooling requires it |
| UI tests | XCUITest plus focused state-machine tests |

Minimum supported versions remain a release-policy decision. The current
implementation and bridge behavior are covered by unit, conformance, and
unsigned application build verification.

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
  ├── CineLarkPluginAPI ───▶ CineLarkDomain
  ├── CineLarkCatalog ─────▶ CineLarkPluginAPI
  ├── CineLarkProfile ─────▶ CineLarkPluginAPI
  ├── CineLarkInsights ────▶ CineLarkProfile
  ├── CineLarkEmby ────────▶ CineLarkPluginAPI
  ├── CineLarkPlayback ──────▶ CineLarkDomain
  ├── CineLarkRemote ────────────▶ Foundation / Security
  ├── CineLarkGateway ───────▶ CineLarkPlayback + CineLarkRemote
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

- Reducers and scoped Stores own observable semantic application state. TCA
  1.26.1 is pinned exactly; hover, animation, live geometry, and transient focus
  remain SwiftUI-local.
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

TCA orchestrates value-typed dependency clients while mutable I/O remains in
independent actors and repositories:

- media-source runtimes own authenticated Emby requests and capability clients;
- `CoreDataCatalogStore` owns recreatable, source-isolated metadata;
- `CoreDataProfileRepository` owns Cloud/Local personal viewing memory;
- the playback launcher owns Rust/IINA process and session ordering;
- the mirror queue serializes retryable provider mutations;
- the Remote coordinator owns pairing, semantic authorization, and sanitized
  broadcasts.

Keychain stores secrets. Core Data backs the local Catalog plus CloudKit/local
Profile configurations. Kingfisher owns the bounded artwork cache. None of
these runtime objects enters TCA State.

### 2.4 Dependencies

Prefer Apple frameworks and small protocol seams first. Add a third-party
library only after the responsible adapter has tests and the dependency reduces
real lifecycle/security complexity. In particular:

- use Kingfisher for artwork delivery instead of growing a custom image stack;
- expose TCA only to the application layer and keep domain/plugin/repository
  modules on pure Swift concurrency;
- isolate Keychain, database, and networking dependencies behind CineLark
  protocols.

## 3. Flutter Remote stack

| Concern | Default |
| --- | --- |
| Framework | current stable Flutter |
| Language | Dart 3 |
| Targets | iOS and Android |
| State | application controller with isolated transport/storage services |
| Navigation | focused screen state; no routing dependency required |
| Serialization | generated contract models plus conformance tests |
| Secrets | Keychain/Keystore through a narrow secure-storage adapter |
| Tests | Dart unit, Flutter widget/golden, and device integration tests |

Current structure:

```text
apps/remote/
  lib/
    controller/          connection and semantic command orchestration
    models/              protocol and rendered state
    screens/             device selection, pairing, and Remote surfaces
    services/            TLS transport and secure credential storage
    widgets/             directional and playback controls
  test/
  integration_test/
```

Rules:

- No provider DTO or credential enters the Flutter project.
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
CineLarkGateway / IINABridgeCenter (bundled Rust executable)
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
| Async/HTTP | Tokio + Axum |
| Serialization | Serde/`serde_json` against shared conformance vectors |
| Logging | `tracing` with mandatory structured redaction |
| Supply chain | locked dependencies, `cargo audit`, `cargo deny` |
| Distribution | signed universal macOS helper embedded in CineLark.app |

Build arm64 and x86_64 artifacts in CI, combine/sign them as part of the app
bundle, and verify the nested code signature. The helper has no provider client,
UI, updater, launch agent, or persistent background mode.

### 4.3 Plugin-facing local API

The internal endpoints are versioned:

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

Credential provisioning and HMAC request/envelope authentication implement
`BRIDGE-SEC-001`. Pairing requires no copied configuration files, edited IINA
preferences, or duplicate account entry.

### 4.5 Zero-configuration delivery

- Bundle the Rust helper inside CineLark.app; no Homebrew, Cargo, shell, admin,
  login item, or separate installer.
- Bundle the matching `.iinaplgz` artifact and drive IINA's official install
  flow from an in-app **Install/Update Bridge** action.
- Detect IINA, plugin, helper, and protocol versions automatically.
- Start/stop the helper on demand and reconnect after IINA restarts.
- Offer clear one-action remediation and a degraded direct-open mode if the
  plugin is unavailable, without blocking library browsing.

### 4.6 Release validation boundary

Automated tests cover dual-loopback binding, bounded requests, authentication,
replay resistance, process framing, replacement playback, and Remote pinned-WSS
forwarding. Release candidates still require physical validation of:

1. IINA `http` requests to both loopback families work with its domain allowlist.
2. Bounded long-poll does not block the plugin queue or degrade playback.
3. Command/event latency is acceptable for pause, seek, and position updates.
4. Port discovery, helper crash recovery, sleep/wake, and multiple IINA windows
   are deterministic.
5. Universal binary size, signing, notarization, and update replacement work
   without user steps.

## 5. Shared-first design

### 5.1 What is shared

| Artifact | Source of truth | Consumers |
| --- | --- | --- |
| Playback state and track semantics | `specs/common/` | Swift, Rust, Dart, plugin |
| App ↔ IINA envelope/messages | `specs/bridge/` | Swift, Rust, TypeScript/JavaScript |
| Remote ↔ Mac envelope/messages | `specs/remote/` | Rust, Swift, Dart |
| Archived provider observation | `specs/uhdnow/` | historical evidence only |
| Compatibility fixtures | `fixtures/conformance/` | all protocol runtimes |
| Color/type/spacing tokens | `shared/design/` | SwiftUI, Flutter |
| Source logo/icon vectors | `shared/brand/` | all applications/plugins |

### 5.2 What is not shared

- SwiftUI/AppKit and Flutter widgets
- provider DTOs or networking clients
- Keychain/Keystore implementations
- Bonjour platform adapters and Flutter certificate-pin integration
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
- Provider-specific time units never appear in shared protocols.

## 6. Remote discovery and security

The recommended design is documented in
[`interfaces/remote-protocol.md`](interfaces/remote-protocol.md):

- Bonjour advertises service identity and protocol range, never secrets.
- Remote transport is WebSocket over TLS in an isolated center of the bundled
  Rust child.
- Pairing uses a high-entropy one-time QR payload and certificate pinning.
- Successful pairing issues a device-scoped revocable credential.
- Remote snapshots exclude provider tokens, playback URLs, and provider DTOs.
- The Mac, not the Rust transport, authorizes login, navigation, text, and
  playback semantics.

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

## 8. Delivered phases

### Phase 0 — foundations implemented

- Deterministic macOS focus/navigation and AppKit input seams are implemented.
- The authenticated loopback IINA center and pinned-WSS Remote center share one
  process shell while retaining isolated protocols and secrets.
- Swift, Rust, JavaScript, and Dart consume shared conformance vectors.
- Flutter implements QR pairing, certificate pinning, secure storage, and
  platform-local networking adapters.

### Phase 1 — native application implemented

- The Swift package graph and TCA application shell are complete.
- Catalog-backed Home, collection, search, favorite, detail, person, cache,
  Profile, and Insights surfaces own their state through scoped Stores.
- The temporary `MediaLibraryProvider` boundary and overlapping observable
  models have been retired.

### Phase 2 — standard Emby implemented

- Discovery, reverse-proxy setup, authentication, hierarchy, search, artwork,
  PlaybackInfo resolution, and Keychain restoration are implemented.
- Local personal state is independent from Emby. Explicit import and durable
  outbound favorite/progress mutation delivery use standard Emby contracts.
- UHDNow subscriptions use standard Emby; the retired source identity only
  participates in an explicit reconnect migration.

### Phase 3 — IINA playback implemented

- The universal Rust helper build, supervised process, provider-neutral IINA
  plugin, resume, telemetry, track control, progress, and sequential episode
  replacement are implemented and covered by automated tests.
- Signed stock-IINA and notarized distribution exercises remain release
  qualification, not missing application architecture.

### Phase 4 — macOS product baseline implemented

- Settings consolidates configuration into General, Profiles & Sources,
  Remote, and Storage. Sidebar/navigation state, cache accounting/purge, source
  setup, Profile recovery, and Viewing Insights are implemented.
- Signing, notarization, performance budgets, accessibility review, and the
  physical two-Mac CloudKit matrix remain release-operator gates.

### Phase 5 — Flutter Remote implemented

- Protocol v1, pairing, multi-Mac credentials, reconnect, remote login,
  navigation, revisioned search, playback/track/volume controls, and revocation
  are implemented.
- Real iOS and Android lifecycle, permission, VPN, and network-transition
  scenarios remain in the physical-device release smoke matrix.

## 9. Intentional future boundaries

- SMB, NFS, WebDAV, DLNA, Plex, multi-source aggregation UI, and managed offline
  downloads are future Source milestones; the current capability/identity/query
  contracts reserve their extension points.
- Collaborative or hosted recommendations require a separate privacy, consent,
  ranking-quality, and backend decision. Current recommendations are local and
  explainable.
- Cross-Apple-ID sharing, child controls, and household permissions are outside
  Profile v1.
- Release policy still owns minimum supported versions, signing/notarization,
  performance thresholds, and physical-device matrices.
