# CineLark

CineLark is a TV-first media library client for macOS. It presents a focused,
remote-friendly browsing experience and delegates playback to IINA/mpv through
an optional thin bridge plugin.

> **Status:** pre-alpha; the native macOS UHDNow vertical slice is now implemented.

## Product family

- **CineLark** — a native Swift/SwiftUI macOS client and system coordinator.
- **CineLark Remote** — a future Flutter companion for iOS and Android; the Mac
  app remains fully usable without it.
- **CineLark IINA Bridge** — a provider-neutral IINA plugin for playback control
  and telemetry.

All components live in this repository so shared contracts can evolve
atomically.

## Architecture

```text
Flutter Remote (iOS / Android)
             │ paired TLS protocol
             ▼
      CineLark for Mac ◀──▶ Media Provider (UHDNow first)
   Swift · SwiftUI · AppKit
             │ child process / stdio
             ▼
   bundled Rust Bridge Helper
             │ loopback-only local protocol
             ▼
  thin IINA JS Plugin → IINA → mpv
```

IINA owns decoding, HDR, audio tracks, subtitles, and presentation. CineLark
owns discovery, provider credentials, resume decisions, and progress updates.
The bridge never receives provider account credentials.

## Repository layout

```text
apps/macos/       native Swift/SwiftUI macOS app
apps/remote/      future Flutter app for iOS and Android
packages/apple/   local Swift package and provider/bridge targets
packages/rust/    bundled, runtime-free bridge helper
plugins/iina/     thin IINA JavaScript adapter
specs/            cross-language contracts and external API observations
shared/           generated-code policy, design tokens, and brand assets
fixtures/         synthetic, redacted test fixtures only
docs/             product, architecture, integration, and decision records
```

## Install

CineLark requires macOS 26 or later and uses an existing IINA installation:

```sh
brew install --cask samsonlab/cinelark/cinelark
```

If IINA is not installed yet:

```sh
brew install --cask iina
```

Tagged releases use a stable project-controlled self-signed identity rather
than Apple notarization. The Cask pins the DMG by SHA-256 and removes quarantine
after installation. The IINA plugin is installed explicitly on first playback.

## Development

```sh
open apps/macos/CineLark.xcodeproj
swift test --package-path packages/apple/CineLarkKit
```

See [`apps/macos/README.md`](apps/macos/README.md) for implemented capabilities
and build details.

## Specifications

Start with [`docs/README.md`](docs/README.md).

- [Product specification](docs/product-spec.md)
- [Architecture](docs/architecture.md)
- [Implementation plan](docs/implementation-plan.md)
- [Media provider interface](docs/interfaces/media-library-provider.md)
- [Metadata cache](docs/interfaces/metadata-cache.md)
- [Playback bridge protocol](docs/interfaces/playback-bridge.md)
- [Rust bridge helper](docs/implementation-plan.md#4-rust-bridge-helper)
- [Remote protocol](docs/interfaces/remote-protocol.md)
- [Homebrew distribution decision](docs/decisions/0005-homebrew-distribution.md)
- [Observed UHDNow API](docs/integrations/uhdnow-api.md)
- [Verified IINA plugin capabilities](docs/integrations/iina-plugin-api.md)

## Security

Do not commit HAR files, extracted captures, credentials, cookies, access
tokens, signed playback URLs, or real account data. See
[`SECURITY.md`](SECURITY.md).

## License

No license has been selected yet. Until one is added, all rights are reserved.
