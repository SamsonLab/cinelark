# Rust Packages

- `cinelark-bridge/` is the loopback-only IINA command/event broker.
- `cinelark-remote-gateway/` is the LAN TLS/WebSocket transport supervised by
  the Mac Remote coordinator.

The helpers are separate executables, secrets, ports, and failure domains. Both
use private framed stdio with the Mac and contain no provider authority.

## `cinelark-bridge`

A self-contained broker bundled and signed inside CineLark.app. It:

- accepts bounded length-prefixed JSON over private parent stdin/stdout;
- binds authenticated HTTP only to `127.0.0.1` and `::1`;
- queues bounded IINA commands and forwards sanitized player events;
- verifies request timestamp/nonce HMACs, envelope HMACs, and sequence order;
- contains no provider client, persistent daemon, updater, or secret storage.

Development commands:

```sh
cargo fmt --manifest-path packages/rust/cinelark-bridge/Cargo.toml --check
cargo test --locked --manifest-path packages/rust/cinelark-bridge/Cargo.toml
cargo clippy --locked --all-targets \
  --manifest-path packages/rust/cinelark-bridge/Cargo.toml -- -D warnings
```

The Xcode build phase produces the app-bundled helper. Release builds compile
both Apple Silicon and Intel targets, combine them with `lipo`, then sign the
nested executable with the app identity. Users require no Cargo installation,
daemon, login item, admin access, or port configuration.
