# CineLark Documentation

This directory describes CineLark's current contributor-facing product,
architecture, interfaces, integrations, and accepted decisions. Historical
feature plans, implementation outcomes, amendments, and engineering runbooks
live in [`docs-ai/`](../docs-ai/README.md).

Documents use the following status labels:

- **Accepted** — an architectural or product decision.
- **Draft** — intended direction; details may change during implementation.
- **Observed** — verified from a capture or source audit, not an official API
  guarantee.
- **Open** — unresolved and must not be treated as a stable contract.

## Product and architecture

| Document | Status | Purpose |
| --- | --- | --- |
| [Product specification](product-spec.md) | Draft | MVP scope, UX principles, and acceptance criteria |
| [Architecture](architecture.md) | Accepted direction | Component boundaries and data ownership |
| [Implementation plan](implementation-plan.md) | Draft | Swift/SwiftUI, Flutter, module, testing, and delivery plan |
| [ADR-0001](decisions/0001-product-monorepo.md) | Accepted | Product monorepo and external IINA policy |
| [ADR-0002](decisions/0002-native-macos-flutter-remote.md) | Accepted | Native macOS and cross-platform Remote stacks |
| [ADR-0003](decisions/0003-bundled-rust-bridge-helper.md) | Accepted direction | Bundled Rust helper and thin IINA adapter |
| [ADR-0004](decisions/0004-iina-bridge-pairing.md) | Phase 0 accepted | Keychain provisioning, authentication, replay resistance, and threat model |
| [ADR-0005](decisions/0005-homebrew-distribution.md) | Accepted, signing superseded | Project Homebrew tap and quarantine-aware distribution |
| [ADR-0006](decisions/0006-sparkle-updates.md) | Accepted | Signed Sparkle feeds and native in-app updates |
| [ADR-0007](decisions/0007-local-automatic-release-signing.md) | Accepted | Local Xcode Automatic Signing, export verification, and publication boundary |
| [ADR-0008](decisions/0008-rust-remote-transport.md) | Accepted | Rust Remote TLS/WebSocket transport with Mac-owned authorization |
| [ADR-0009](decisions/0009-unified-native-gateway.md) | Accepted direction | Unified native gateway boundary |
| [ADR-0010](decisions/0010-tca-application-boundary.md) | Accepted | TCA application boundary and Swift-concurrency service isolation |

## Interfaces

| Document | Status | Purpose |
| --- | --- | --- |
| [Media library provider](interfaces/media-library-provider.md) | Legacy internal adapter | Previous provider boundary retained below the UHDNow plugin only |
| [Media source platform](interfaces/media-source-platform.md) | Implemented v1 | Capability-based plugin, identity, query, and runtime contracts |
| [Profile and CloudKit persistence](interfaces/profile-cloudkit-schema.md) | Implemented; release smoke pending | Cloud/local entity placement, conflict, import, and mirror rules |
| [Cache management](interfaces/metadata-cache.md) | Accepted implementation | Catalog/artwork accounting, purge, and user-data boundaries |
| [Playback bridge](interfaces/playback-bridge.md) | Draft, Phase 0 implemented | Mac app ↔ IINA protocol |
| [Remote protocol](interfaces/remote-protocol.md) | Implemented v1 | Flutter Remote ↔ Rust gateway ↔ Mac protocol |
| [`specs/common/playback.schema.json`](../specs/common/playback.schema.json) | Draft | Cross-language playback state types |
| [`specs/bridge/envelope.schema.json`](../specs/bridge/envelope.schema.json) | Draft | Bridge message envelope schema |
| [`specs/remote/envelope.schema.json`](../specs/remote/envelope.schema.json) | Version 1 | Remote message envelope schema |

## Integrations

| Document | Status | Purpose |
| --- | --- | --- |
| [UHDNow API](integrations/uhdnow-api.md) | Observed | Sanitized endpoint and model inventory |
| [Emby integration](integrations/emby.md) | Implemented v1 | Discovery, authentication, content mapping, playback, import, and mirror |
| [`specs/uhdnow/openapi.yaml`](../specs/uhdnow/openapi.yaml) | Observed, partial | Machine-readable endpoint contract |
| [IINA plugin API](integrations/iina-plugin-api.md) | Verified snapshot | Available playback/plugin capabilities and gaps |

External APIs documented here may change without notice. Provider adapters must
isolate that volatility from CineLark's domain model.
