# 011 — Media Source Platform: Foundation Action

| | |
| --- | --- |
| **Status** | Implemented and verified |
| **Date** | 2026-08-26 |
| **Scope** | Plugin contracts, Catalog, Profile persistence, and Emby v1 |

## Implemented

- Added independent `CineLarkPluginAPI`, `CineLarkCatalog`, and `CineLarkEmby`
  SwiftPM products.
- Added stable plugin/source/instance/locator/catalog/content identities,
  source-set queries, opaque cursors, optional totals, and capability
  descriptors.
- Added static factory registration and an actor-owned runtime platform.
- Added a local Core Data catalog with exact source isolation and one-to-many
  locator support. Matching external IDs do not merge records implicitly.
- Added bounded `bufferingNewest(1)` catalog and source change streams.
- Proved the initial capability runtime with UHDNow, then consolidated that
  source into standard Emby with an explicit legacy reconnect migration.
- Added Emby reverse-proxy-safe URL construction, public-system validation,
  device headers, user authentication, offset pagination, search/browse mapping,
  header-authenticated artwork, direct playback resolution, and playback
  check-in endpoints.
- Added an account-scoped Keychain secret store. Tokens are not placed in media
  or artwork URLs.
- Added UDP 7359 discovery, manual/reverse-proxy URL setup, validation,
  authentication, Keychain token persistence, and persisted runtime restore.
- Completed Emby Views, Items, Latest, Resume, detail, Seasons, Episodes,
  People, favorites/import, PlaybackInfo resolution, and playback check-ins.
- Added a CloudKit/local dual-store Profile repository, deterministic conflict
  ordering, explicit idempotent import markers, unique mirror ownership, and a
  persistent retry queue.
- Replaced all macOS UI-facing provider reads with Catalog-backed TCA feature
  projections.

## Verification

- `swift test` passes all 55 package tests across 7 suites.
- New tests cover duplicate plugin IDs, source isolation, explicit multi-locator
  identity, non-merging content keys, reverse proxy base paths, opaque-to-offset
  cursor mapping, stable device headers, discovery parsing, full hierarchy and
  image mapping, import/mirror endpoints, and token redaction from URLs.
- The macOS composition root statically registers the standard Emby source and
  builds against the new products. A legacy plugin ID is recognized only to
  present a reconnect proposal; it does not install a separate runtime.

Current aggregate verification on 2026-08-28 passes 67 Swift package tests, 38
Swift Testing macOS tests, 6 macOS XCTest cases, and an unsigned Release build.

## Remaining integration checks

- Run a signed two-device CloudKit smoke test with the production/development
  container schema deployed for the selected environment.

Authenticated artwork delivery was completed and verified in
[019 — Authenticated artwork delivery](../019-authenticated-artwork-delivery/001-action.md).
