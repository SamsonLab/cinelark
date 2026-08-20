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
| [ADR-0001](decisions/0001-product-monorepo.md) | Accepted | Product monorepo and external IINA policy |

## Interfaces

| Document | Status | Purpose |
| --- | --- | --- |
| [Media library provider](interfaces/media-library-provider.md) | Draft | Provider-neutral domain boundary |
| [Playback bridge](interfaces/playback-bridge.md) | Draft, security blocked | App ↔ IINA protocol |
| [`specs/bridge/envelope.schema.json`](../specs/bridge/envelope.schema.json) | Draft | Bridge message envelope schema |

## Integrations

| Document | Status | Purpose |
| --- | --- | --- |
| [UHDNow API](integrations/uhdnow-api.md) | Observed | Sanitized endpoint and model inventory |
| [`specs/uhdnow/openapi.yaml`](../specs/uhdnow/openapi.yaml) | Observed, partial | Machine-readable endpoint contract |
| [IINA plugin API](integrations/iina-plugin-api.md) | Verified snapshot | Available playback/plugin capabilities and gaps |

External APIs documented here may change without notice. Provider adapters must
isolate that volatility from CineLark's domain model.
