# CineLark Architecture

- **Status:** Accepted direction; implementation details remain Draft
- **Last updated:** 2026-08-20

## 1. System context

```text
                       ┌────────────────────┐
                       │ CineLark Remote    │
                       │ Flutter mobile app │
                       └─────────┬──────────┘
                                 │ paired local protocol
                                 ▼
┌────────────────┐      ┌───────────────────────────────┐
│ Media Provider │◀────▶│ CineLark for Mac             │
│ UHDNow first   │      │                               │
└────────────────┘      │ UI + domain + provider auth   │
                        │ PlaybackCoordinator           │
                        └───────────────┬───────────────┘
                                        │ private child stdio
                                        ▼
                        ┌───────────────────────────────┐
                        │ bundled Rust Bridge Helper    │
                        └───────────────┬───────────────┘
                                        │ loopback-only HTTP
                                        ▼
                        ┌───────────────────────────────┐
                        │ thin IINA JavaScript Plugin   │
                        └───────────────┬───────────────┘
                                        ▼
                                   IINA / mpv
```

## 2. Ownership rules

| Concern | Owner |
| --- | --- |
| Account credentials and provider token | Provider adapter in Mac app |
| Keychain lifecycle | Mac app; plugin stores only its bridge secret |
| Library, detail, favorites, resume source | Provider adapter |
| Navigation and focus | Mac app presentation layer |
| Version selection | Mac app `PlaybackCoordinator` |
| Playback URL construction | Provider adapter |
| Decode, HDR, tracks, subtitles | IINA/mpv |
| Player transport and telemetry | Rust Bridge Helper + IINA plugin |
| Provider progress writes | Mac app |
| Remote pairing and authorization | Mac app |

The plugin never calls provider APIs. The Remote never receives provider
credentials or directly controls the plugin.

## 3. Logical modules

The Mac implementation is Apple-native: Swift 6 with strict concurrency,
SwiftUI for product UI, and focused AppKit adapters where macOS windowing,
input, or focus behavior requires them. Apple modules live as targets in one
local Swift package initially. The Remote is a separate Flutter/Dart runtime;
shared behavior crosses that boundary through versioned schemas and conformance
fixtures, not linked Swift code.

### 3.1 `CineLarkDomain`

Provider-neutral value types and use cases:

- media identifiers, summaries, details, seasons, episodes, and people
- image references and playback state
- media assets, audio/subtitle tracks, and playback descriptors
- pagination, sorting, favorites, and provider errors

It contains no networking, UI framework, UHDNow JSON, or IINA API types.

### 3.2 `MediaLibraryProvider`

An asynchronous capability boundary described in
[`interfaces/media-library-provider.md`](interfaces/media-library-provider.md).
Provider adapters translate unstable external contracts into stable domain
models.

### 3.3 `UHDNowProvider`

Owns:

- authentication and raw `Authorization` token transport
- `/api/v1` request/response models
- line/domain resolution and tokenized playback URL construction
- tick/second conversion
- UHDNow-specific paging, sorting, and item-type mapping

Raw DTOs stay internal to this package.

### 3.4 `PersistentMetadataCache`

An actor-isolated, bounded file store for recreatable domain metadata. A
provider-neutral read-through decorator applies per-resource TTLs, stale outage
fallback, tagged invalidation, schema resets, and account-lifecycle clearing.
Playback descriptors and provider capabilities are never persisted. Artwork
uses a separate bounded Kingfisher memory/disk pipeline.

See [`interfaces/metadata-cache.md`](interfaces/metadata-cache.md).

### 3.5 `CineLarkApplication`

Coordinates use cases and state machines. It depends on domain protocols, not
concrete provider or bridge implementations.

### 3.6 `PlaybackCoordinator`

Maintains one logical playback session:

1. Resolve provider item and selected media asset.
2. Decide resume/start-over position.
3. Request an ephemeral playback descriptor.
4. Connect and authenticate the IINA Bridge.
5. Send provider-neutral `play` command.
6. Translate bridge telemetry into local state.
7. Coalesce and write provider progress.
8. Send a final stopped update and close the logical session.

A new `play` supersedes the previous logical session and finalizes it first.

### 3.7 `RustBridgeHelper`

A self-contained native helper bundled and signed inside CineLark.app. The Mac
supervises it as a child process and exchanges framed JSON over stdio. It exposes
an authenticated loopback-only HTTP/long-poll endpoint to the IINA plugin,
validates bridge envelopes, orders sessions, and contains no provider logic or
persistent daemon behavior.

### 3.8 `IINABridgePlugin`

A minimal JavaScript/TypeScript package with no provider dependency. It polls
the Rust helper for commands, posts sanitized events, and maps the bridge
protocol to IINA public plugin APIs and mpv properties/events.

### 3.9 `RemoteGateway`

A native Mac service that publishes sanitized app/player snapshots and accepts
capability-checked semantic commands. It owns Bonjour discovery, secure pairing,
device revocation, protocol negotiation, and the TLS endpoint. It never exposes
provider DTOs, credentials, or playback URLs.

### 3.10 `CineLarkRemote`

A Flutter application for iOS and Android. It mirrors only the state required by
the companion experience and sends semantic navigation/playback commands to the
Mac. Discovery, secure storage, notifications, and certificate pinning stay
behind Flutter infrastructure adapters or narrowly scoped platform channels.

## 4. Data flow

### 4.1 Browse

```text
View → Use Case → CachedMediaLibraryProvider → fresh metadata cache
                           │
                           └→ Provider API → cache replacement
View ← View State ← Domain Models ← cached or mapped provider data
```

Expired metadata falls back to stale data only for transient provider failures.
Views never depend on provider DTOs.

### 4.2 Play and resume

```text
Selection
  → provider.assets(item)
  → choose asset
  → provider.makePlaybackDescriptor(asset)
  → bridge.play(descriptor, startPosition)
  → Rust helper queues authenticated command
  → IINA plugin calls core.open(url)
  → file-loaded
  → seekTo(startPosition)
  → state/position events
  → provider.reportProgress(...)
```

Resume is applied after a matching `file-loaded` event, not merely after sending
`open`, to avoid races with mpv initialization.

### 4.3 Progress

Bridge telemetry uses seconds. Provider adapters convert at their boundary.
UHDNow uses 10,000,000 ticks per second:

```text
positionTicks = round(positionSeconds × 10,000,000)
positionSeconds = positionTicks ÷ 10,000,000
```

The coordinator periodically coalesces position changes and sends a terminal
stopped event for lifecycle boundaries. Exact cadence and retry policy are Open.

## 5. State and concurrency

- SwiftUI observes `@MainActor` feature models built with the Observation
  framework; domain values remain immutable and UI-independent.
- Provider sessions, bridge sessions, image/cache coordination, and progress
  writes use Swift actors and structured concurrency.
- Provider and bridge operations support cancellation.
- Each playback session has a unique opaque ID; late events from superseded
  sessions are ignored.
- Progress writes for one item are serialized and monotonic unless the user
  explicitly seeks backward.
- Provider token refresh/login changes invalidate derived playback URLs.

## 6. Failure boundaries

| Failure | Required behavior |
| --- | --- |
| Provider unavailable | Preserve navigation state; show retry affordance |
| Session expired | Reauthenticate without exposing credentials to plugin |
| Asset/domain resolution failed | Do not launch IINA; offer retry/version change |
| IINA absent | Explain installation requirement; library remains usable |
| Plugin absent/incompatible | Show detected protocol versions and remediation |
| Bridge disconnected | Keep provider state; reconnect or terminate session cleanly |
| Progress write failed | Coalesce retry; never pause playback |
| Tokenized URL expired | Resolve a new descriptor instead of replaying cached URL |

## 7. Security boundaries

- External provider traffic uses HTTPS.
- The Mac app is the only component allowed to hold provider credentials.
- Playback descriptors are ephemeral and must not be persisted.
- Bridge traffic is local but still untrusted until authenticated.
- The preferred Rust helper binds explicitly to loopback and authenticates the
  plugin; the Mac side uses private child-process stdio.
- The audited IINA WebSocket server is not loopback-restricted and has no TLS,
  so it is not the default transport. Any fallback requires a separate security
  review.
- Remote traffic uses authenticated TLS, explicit pairing, certificate pinning,
  device-scoped credentials, and revocation.
- Every diagnostic layer applies structured redaction before formatting values.

## 8. Repository boundaries

```text
apps/macos/                         SwiftUI macOS app and Xcode project
apps/remote/                        Flutter app for iOS and Android
packages/apple/CineLarkKit/         local Swift package with focused targets
packages/rust/cinelark-bridge/      bundled, signed native helper
plugins/iina/                       minimal JavaScript/TypeScript adapter
specs/common/                       cross-language domain/wire primitives
specs/bridge/                       Mac app ↔ IINA contracts
specs/remote/                       Flutter Remote ↔ Mac app contracts
specs/uhdnow/                       observed external API description
shared/design/                      platform-neutral design tokens
shared/brand/                       source vector brand assets
fixtures/conformance/               sanitized cross-runtime protocol vectors
```

Generated Swift/Rust/Dart/TypeScript files are outputs, never the source of truth.
The exact code generator remains an implementation spike; schema compatibility
and conformance vectors are required even if a runtime initially uses handwritten
adapters.

## 9. Testing strategy

- Domain: pure unit tests for mapping-independent behavior and resume rules.
- Provider: contract tests against synthetic redacted fixtures.
- Bridge: shared schema vectors in Swift, Rust, and JavaScript; helper process,
  loopback binding, long-poll latency, crash, and reconnect integration tests.
- Remote: shared schema vectors executed by Swift and Dart, plus pairing,
  reconnect, revocation, and stale-command tests.
- Playback: integration tests with a local fake bridge before IINA automation.
- macOS UI: deterministic focus-navigation tests for rows, grids, detail pages,
  and state restoration.
- Flutter UI: widget/golden tests for controls and connection states, with
  platform integration tests for discovery and secure storage.
- Security: secret scanning and URL/header redaction tests in CI.
