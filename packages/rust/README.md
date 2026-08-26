# Rust Packages

`cinelark-gateway/` is the single native transport helper bundled and signed
inside CineLark.app. It contains two independent code-level centers:

- `IINABridgeCenter` owns authenticated loopback HTTP, bounded IINA commands,
  player events, and the plugin secret.
- `RemoteGatewayCenter` owns LAN TLS/WebSocket, identity, pairing expiry, device
  authentication, sequencing, and rate limits.

The centers share one process shell, Tokio runtime, framed parent stdio, and
linked dependencies. They do not share secrets, ports, protocols, state, or
semantic authority. The Mac remains the only component that can perform product
operations.

Development commands:

```sh
cargo +1.95.0 fmt --manifest-path packages/rust/cinelark-gateway/Cargo.toml --check
cargo +1.95.0 test --locked --manifest-path packages/rust/cinelark-gateway/Cargo.toml
cargo +1.95.0 clippy --locked --all-targets \
  --manifest-path packages/rust/cinelark-gateway/Cargo.toml -- -D warnings
python3 scripts/test_bridge_process.py \
  --executable packages/rust/cinelark-gateway/target/debug/cinelark-gateway
```

The Xcode build phase produces one app-bundled helper. Release builds compile
Apple Silicon and Intel targets, combine them with `lipo`, and sign the nested
executable with the app identity. Users require no Cargo installation, daemon,
login item, admin access, or port configuration.
