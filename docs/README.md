# CineLark Documentation

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

## Interfaces

| Document | Status | Purpose |
| --- | --- | --- |
| [Media library provider](interfaces/media-library-provider.md) | Draft | Provider-neutral domain boundary |
| [Metadata cache](interfaces/metadata-cache.md) | Accepted implementation | Durable metadata and artwork-cache boundaries |
| [Playback bridge](interfaces/playback-bridge.md) | Draft, Phase 0 implemented | Mac app ↔ IINA protocol |
| [Remote protocol](interfaces/remote-protocol.md) | Draft | Flutter Remote ↔ Mac app protocol |
| [`specs/common/playback.schema.json`](../specs/common/playback.schema.json) | Draft | Cross-language playback state types |
| [`specs/bridge/envelope.schema.json`](../specs/bridge/envelope.schema.json) | Draft | Bridge message envelope schema |
| [`specs/remote/envelope.schema.json`](../specs/remote/envelope.schema.json) | Draft | Remote message envelope schema |

## Integrations

| Document | Status | Purpose |
| --- | --- | --- |
| [UHDNow API](integrations/uhdnow-api.md) | Observed | Sanitized endpoint and model inventory |
| [`specs/uhdnow/openapi.yaml`](../specs/uhdnow/openapi.yaml) | Observed, partial | Machine-readable endpoint contract |
| [IINA plugin API](integrations/iina-plugin-api.md) | Verified snapshot | Available playback/plugin capabilities and gaps |

External APIs documented here may change without notice. Provider adapters must
isolate that volatility from CineLark's domain model.
