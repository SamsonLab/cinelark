# CineLark

CineLark is a TV-first media library client for macOS. It presents a focused,
remote-friendly browsing experience and delegates playback to IINA/mpv through
an optional thin bridge plugin.

> **Status:** pre-alpha; product and interface specifications only.

## Product family

- **CineLark** — the macOS library client and system coordinator.
- **CineLark Remote** — a future iPhone companion; the Mac app remains fully
  usable without it.
- **CineLark IINA Bridge** — a provider-neutral IINA plugin for playback control
  and telemetry.

All components live in this repository so shared contracts can evolve
atomically.

## Architecture

```text
Media Provider (UHDNow first)
            │
            ▼
      CineLark for Mac
  library · auth · progress
            │
     authenticated local bridge
            │
            ▼
 CineLark IINA Bridge → IINA → mpv
```

IINA owns decoding, HDR, audio tracks, subtitles, and presentation. CineLark
owns discovery, provider credentials, resume decisions, and progress updates.
The bridge never receives provider account credentials.

## Repository layout

```text
apps/          macOS app and future iPhone Remote
packages/      shared domain and provider packages
plugins/iina/  thin IINA playback bridge
specs/         machine-readable external and internal contracts
fixtures/      synthetic, redacted test fixtures only
docs/          product, architecture, integration, and decision records
```

## Specifications

Start with [`docs/README.md`](docs/README.md).

- [Product specification](docs/product-spec.md)
- [Architecture](docs/architecture.md)
- [Media provider interface](docs/interfaces/media-library-provider.md)
- [Playback bridge protocol](docs/interfaces/playback-bridge.md)
- [Observed UHDNow API](docs/integrations/uhdnow-api.md)
- [Verified IINA plugin capabilities](docs/integrations/iina-plugin-api.md)

## Security

Do not commit HAR files, extracted captures, credentials, cookies, access
tokens, signed playback URLs, or real account data. See
[`SECURITY.md`](SECURITY.md).

## License

No license has been selected yet. Until one is added, all rights are reserved.
