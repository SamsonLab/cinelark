# Implementation Packages

The initial Apple implementation uses one local Swift package at
`apple/CineLarkKit/` with multiple focused targets:

- `CineLarkDomain` — provider-neutral models and protocols.
- `CineLarkPluginAPI` — source identities, capability clients, registry, and runtime contracts.
- `CineLarkCatalog` — normalized local metadata and query cache.
- `CineLarkProfile` — local/CloudKit Profile state and viewing facts.
- `CineLarkInsights` — rebuildable viewing-memory projections.
- `CineLarkEmby` — standard Emby discovery, authentication, mapping, and playback reporting.
- `CineLarkPlayback` — IINA playback state and its center transport contract.
- `CineLarkRemote` — typed child-process protocol, Keychain-backed Remote
  identity/device records, and Remote center transport contract. The Mac
  app owns semantic command dispatch and sanitized snapshots.
- `CineLarkGateway` — one process shell with independent `IINABridgeCenter` and
  `RemoteGatewayCenter` actors.
- `CineLarkPersistence` — Keychain secret storage and narrow persistence migrations.

Dependencies point inward: adapters depend on domain contracts; domain code does
not import provider, UI, Flutter, or IINA types. Cross-language sharing belongs
under `specs/` and `shared/`, not this directory.

The bundled Rust helper lives at `rust/cinelark-gateway/`. It is compiled into a
self-contained universal executable inside the Mac app; users do not install a
Rust toolchain or runtime.
