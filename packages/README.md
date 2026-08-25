# Implementation Packages

The initial Apple implementation uses one local Swift package at
`apple/CineLarkKit/` with multiple focused targets:

- `CineLarkDomain` — provider-neutral models and protocols.
- `CineLarkApplication` — use cases and coordination state machines.
- `CineLarkUHDNow` — UHDNow API adapter and DTOs.
- `CineLarkBridgeClient` — child-process client for the Rust bridge helper.
- `CineLarkRemote` — typed child-process protocol, Keychain-backed Remote
  identity/device records, and Remote gateway supervision primitives. The Mac
  app owns semantic command dispatch and sanitized snapshots.
- `CineLarkPersistence` — Keychain and non-secret cache abstractions.
- `CineLarkDesignSystem` — reusable native presentation primitives.
- `CineLarkTestSupport` — synthetic factories and shared test utilities.

Dependencies point inward: adapters depend on domain contracts; domain code does
not import provider, UI, Flutter, or IINA types. Cross-language sharing belongs
under `specs/` and `shared/`, not this directory.

Bundled Rust helpers live at `rust/cinelark-bridge/` and
`rust/cinelark-remote-gateway/`. They are compiled into self-contained universal
executables inside the Mac app; users do not install a Rust toolchain or runtime.
