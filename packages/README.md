# Implementation Packages

The initial Apple implementation uses one local Swift package at
`apple/CineLarkKit/` with multiple focused targets:

- `CineLarkDomain` — provider-neutral models and protocols.
- `CineLarkApplication` — use cases and coordination state machines.
- `CineLarkUHDNow` — UHDNow API adapter and DTOs.
- `CineLarkBridgeClient` — child-process client for the Rust bridge helper.
- `CineLarkRemoteGateway` — native Remote server and pairing coordinator.
- `CineLarkPersistence` — Keychain and non-secret cache abstractions.
- `CineLarkDesignSystem` — reusable native presentation primitives.
- `CineLarkTestSupport` — synthetic factories and shared test utilities.

Dependencies point inward: adapters depend on domain contracts; domain code does
not import provider, UI, Flutter, or IINA types. Cross-language sharing belongs
under `specs/` and `shared/`, not this directory.

The bundled Rust broker will live at `rust/cinelark-bridge/`. It is compiled
into a self-contained universal helper inside the Mac app; users do not install
a Rust toolchain or runtime.
