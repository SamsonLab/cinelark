# 009 — Unified Native Gateway: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-26 | Replaced two Rust crates and executables with `cinelark-gateway` | `packages/rust/cinelark-gateway` |
| 2026-08-26 | Kept independent Rust IINA and Remote centers behind namespaced parent IPC | `iina_center.rs`, `remote_center.rs`, `parent_protocol.rs` |
| 2026-08-26 | Added one Swift process shell with two typed actor facades | `packages/apple/CineLarkKit/Sources/CineLarkGateway` |
| 2026-08-26 | Injected the two center transports into playback and Remote coordinators | `CineLarkApp.swift` |
| 2026-08-26 | Updated Xcode, CI, and release packaging to build, strip, sign, and verify one helper | `apps/macos/project.yml`, `.github/workflows/bridge.yml`, `scripts/package_macos_release.sh` |
| 2026-08-26 | Superseded ADR-0008's separate-process choice after measuring packaging cost | `docs/decisions/0009-unified-native-gateway.md` |

## Outcome & current state (as of 2026-08-26)

CineLark bundles one `Contents/Helpers/CineLarkGateway` executable. The process
shell owns the Tokio runtime and length-prefixed parent stdin/stdout. Every
parent frame is routed through an explicit `iina`, `remote`, or `process`
namespace.

`IINABridgeCenter` still owns only loopback HTTP, the plugin HMAC secret,
command ordering, and IINA events. `RemoteGatewayCenter` still owns only LAN
TLS/WSS, TLS identity, pairing expiry, device credentials, sequencing, and rate
limits. Center-scoped shutdown is independently restartable and does not stop
the other listener. The IINA plugin wire protocol and Flutter Remote WSS wire
protocol are unchanged.

Swift exposes matching `IINABridgeCenter` and `RemoteGatewayCenter` actors over
one `GatewayProcessShell`. Playback and Remote depend on typed transport
protocols and cannot address the other center. The composition root owns the
shared process lifecycle and performs process-scoped shutdown at app
termination.

Release builds strip local Rust symbols before nested signing. The built app
contains exactly one helper.

## Size result

| Artifact | 0.1.9 separate helpers | Unified gateway | Delta |
| --- | ---: | ---: | ---: |
| Universal Rust helper executable(s) | 18,174,256 B | 13,355,328 B | -4,818,928 B (-26.5%) |
| Repacked UDZO app image | 17,010,348 B | 15,661,099 B | -1,349,249 B (-7.9%) |

The DMG comparison uses the installed signed 0.1.9 app and a stripped unsigned
universal build of the unified app, both repacked locally with the same UDZO
command. Final signing metadata may move the exact published size slightly.
The Remote TLS/crypto stack remains required, so the app cannot return to the
0.1.8 size merely by deduplicating the helper process.

## Validation

- `cargo +1.95.0 fmt --manifest-path packages/rust/cinelark-gateway/Cargo.toml --check` passed.
- `cargo +1.95.0 clippy --locked --all-targets --manifest-path packages/rust/cinelark-gateway/Cargo.toml -- -D warnings` passed.
- `cargo +1.95.0 test --locked --manifest-path packages/rust/cinelark-gateway/Cargo.toml` passed all 26 tests.
- `scripts/test_bridge_process.py` passed against the unified executable and
  verified that IINA can stop/restart while Remote stays configured.
- `swift test` passed all 41 CineLarkKit tests.
- The macOS Xcode suite passed all 11 tests with code signing disabled.
- A stripped Release universal app build succeeded for arm64 and x86_64 and
  contained only `Contents/Helpers/CineLarkGateway`.

## Deviations from plan

- The plan expected to record only linked-binary deduplication. Release symbol
  stripping was added after measurement showed another safe 1.9 MB reduction in
  the universal helper.

## Open questions

- Validate one signed/notarized build on Intel hardware before the next public
  release.
- Record the exact published DMG size after the next release is signed.
