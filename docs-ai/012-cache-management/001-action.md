# 012 — Cache Management: Action

| | |
| --- | --- |
| **Status** | Implemented and verified |
| **Date** | 2026-08-26 |
| **Scope** | Catalog and artwork accounting, safe purge, Settings UI, and effect coordination |

## Implemented

- Added logical Catalog cache statistics for item, locator, query, and payload
  storage, plus a recreatable-data purge operation.
- Added a TCA `CacheClient` that originally aggregated the Catalog, legacy
  metadata migration directory, and Kingfisher artwork disk cache.
- Added `CacheFeature` with latest-wins accounting, confirmation, progress,
  normalized failures, and a post-clear usage refresh.
- Added a standard macOS Settings scene showing metadata, artwork, and total
  on-disk usage with a destructive `Clear Cache` action.
- Clearing evicts Kingfisher memory/disk data and removes Catalog metadata while
  preserving Profiles, favorites, playback progress, source
  configuration, Keychain credentials, and Remote pairing records.
- `CacheFeature` emits `willClear` before infrastructure deletion. `AppFeature`
  uses that delegate to cancel Library/Search Catalog writers and remove detail
  routes, preventing an in-flight refresh from immediately repopulating a cache
  the user just cleared.
- The old provider/cache implementation remained outside application state and
  UI ownership at this milestone. It was subsequently removed by
  [020 — Legacy provider retirement](../020-legacy-provider-retirement/001-action.md);
  startup now performs the one-time artifact cleanup independently of Settings.

## Verification

- `swift test` passes 56 tests across 7 SwiftPM suites.
- `CoreDataCatalogStoreTests.cacheStatisticsAndPurgeCoverOnlyRecreatableCatalogData`
  verifies non-zero logical usage, complete Catalog purge, and an empty cached
  query afterward.
- `CacheFeatureTests.clearAndReload` verifies confirmation, the pre-clear
  delegate boundary, successful clearing, the post-clear delegate, and the
  refreshed zero usage projection.
- Unsigned `xcodebuild test` passes 16 Swift Testing tests across 9 suites and
  the existing 6 XCTest cases.

## Deviations from the plan

- Clear operations for Catalog metadata and artwork run
  independently and aggregate failures. This lets each cache attempt eviction
  even if another category fails.
- A parent coordination delegate was added after identifying the in-flight
  Catalog writer race. Cache infrastructure alone cannot cancel feature-owned
  effects safely.

## Follow-up

- Offline downloads remain a separate future cache category with their own
  retention and per-item deletion semantics.
- Physical SQLite file diagnostics may be added as developer-only telemetry;
  user-facing usage intentionally reports logical media payload so a cleared
  Catalog reads as zero.
