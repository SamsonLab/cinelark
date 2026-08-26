# CineLark Architecture

- **Status:** Accepted direction; implementation details remain Draft
- **Last updated:** 2026-08-20

## 1. System context

```text
                       ┌────────────────────┐
                       │ CineLark Remote    │
                       │ Flutter mobile app │
                       └─────────┬──────────┘
                                 │ pinned WSS on LAN
                                 ▼
                       ┌───────────────────────────────┐
                       │ Rust Remote Gateway Transport │
                       └─────────┬─────────────────────┘
                                 │ private child stdio
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
| Remote TLS, framing, proof verification, sequencing, and rate limits | Rust Remote Gateway |
| Remote pairing approval, device records, capabilities, and semantic authorization | Mac app |

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

### 3.7 `CineLarkGateway`

A self-contained native helper bundled and signed inside CineLark.app. The Mac
supervises one child process and exchanges center-namespaced framed JSON over
stdio. The process shell and Tokio runtime are shared; `IINABridgeCenter` and
`RemoteGatewayCenter` retain separate state, protocols, credentials, ports, and
network boundaries. The helper contains no provider logic or persistent daemon
behavior.

### 3.8 `IINABridgePlugin`

A minimal JavaScript/TypeScript package with no provider dependency. It polls
the Rust helper for commands, posts sanitized events, and maps the bridge
protocol to IINA public plugin APIs and mpv properties/events.

### 3.9 `RemoteGatewayCenter`

The Remote center inside the bundled Rust child owns the LAN TLS/WebSocket
endpoint, certificate fingerprinting, frame limits, pairing-secret expiry,
device proof verification, per-connection sequencing, and rate limits. It
forwards only authenticated envelopes to the Mac over private length-prefixed
JSON stdio. It has no provider, navigation, or playback authority and remains
isolated at the code, state, protocol, credential, port, and listener layers
from the loopback-only IINA bridge center.

See [ADR-0009](decisions/0009-unified-native-gateway.md).

### 3.10 `RemoteGatewayCoordinator`

A Mac application service owns TLS identity/device-record persistence, pairing
presentation and approval, Bonjour advertisement, capability calculation,
snapshot publication, and semantic-command authorization. It dispatches
navigation through the same command layer as local keyboard input and delegates
playback operations to `PlaybackCoordinator`. It never exposes provider DTOs,
credentials, playback URLs, or SwiftUI view identities.

### 3.11 `CineLarkRemote`

A focused Flutter application for iOS and Android. It provides contextual
pairing, login, navigation, search text-entry, and now-playing control surfaces.
It does not contact providers or play media locally. QR scanning, certificate
pinning, secure storage, camera/local-network permissions, and lifecycle
reconnect stay behind Flutter infrastructure adapters or narrow platform
channels.

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

For series episodes, CineLark discovers the ordered remainder of the series in
the background but keeps no future URL in IINA's playlist. At natural EOF it
reports the completed item, resolves the next episode's asset and capability
URL, sends `player.stop` for the completed session, and then sends the new
`player.play` command. This matches a second manual in-app play action. The
global plugin posts both commands to the same managed player ID while the player
plugin calls `core.open` to replace its single content item. The incoming
session does not become terminal-eligible before its own `file-loaded`, and a
replacement timeout never creates another player window. The managed player
sets mpv `keep-open=yes` so IINA cannot close the window before replacement.
Natural EOF is observed from mpv's
`eof-reached` property because IINA's generic JavaScript event callbacks do not
expose `end-file` details. A
telemetry gap may request a fresh state snapshot but does not
clear the continuation metadata. Capability URLs are generated only when their
episode is about to open.

### 4.3 Progress

Bridge telemetry uses seconds. Provider adapters convert at their boundary.
UHDNow uses 10,000,000 ticks per second:

```text
positionTicks = round(positionSeconds × 10,000,000)
positionSeconds = positionTicks ÷ 10,000,000
```

The coordinator uploads one immutable snapshot when an item becomes active and
periodically coalesces later position changes. Timers are playback-ID scoped,
and the serial synchronization worker retains only the latest pending progress
snapshot for a slow provider. A terminal stopped snapshot forms an ordering
barrier before a replacement item's first progress write. Successful terminal
writes drive cache invalidation, observable playback revision, and serialized
App refresh; failed writes do not advance local synchronization state. Exact
retry policy is Open.

## 5. State and concurrency

- SwiftUI observes `@MainActor` feature models built with the Observation
  framework; domain values remain immutable and UI-independent.
- Provider sessions, bridge sessions, image/cache coordination, and progress
  writes use Swift actors and structured concurrency.
- Provider and bridge operations support cancellation.
- Each playback session has a unique opaque ID; late events from superseded
  sessions are ignored.
- Progress writes are immutable, playback-ID scoped, serialized across item
  replacement, and monotonic within an item unless the user explicitly seeks
  backward. Pending non-terminal writes for one playback may be coalesced.
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
- Remote traffic terminates in the isolated Rust gateway and uses TLS, explicit
  pairing, certificate pinning, connection-bound device proofs, device-scoped
  credentials, exact sequencing, rate limits, and revocation. The Mac remains
  the only semantic authorization authority.
- Every diagnostic layer applies structured redaction before formatting values.

## 8. Repository boundaries

```text
apps/macos/                         SwiftUI macOS app and Xcode project
apps/remote/                        Flutter app for iOS and Android
packages/apple/CineLarkKit/         local Swift package with focused targets
packages/rust/cinelark-gateway/     one helper with independent IINA and Remote centers
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
- Remote: shared schema/cryptographic vectors executed by Rust, Swift, and Dart;
  pinned-WSS pairing/authenticated-forwarding coverage; plus one-time secret,
  sequencing, rate-limit, stable-error, playback-navigation, and text-revision
  regressions. Physical-device reconnect and revocation remain release smokes.
- Playback: integration tests with a local fake bridge before IINA automation.
- macOS UI: deterministic focus-navigation tests for rows, grids, detail pages,
  and state restoration.
- Flutter UI: widget/golden tests for controls and connection states, with
  platform integration tests for discovery and secure storage.
- Security: secret scanning and URL/header redaction tests in CI.
