# 012 — Cache Management: Plan

| | |
| --- | --- |
| **Status** | Implemented and verified |
| **Anchor date** | 2026-08-26 |
| **Primary refs** | `CacheFeature`, `CacheClient`, `CoreDataCatalogStore`, `CacheSettingsView` |
| **Related** | [`../011-media-source-platform/000-plan.md`](../011-media-source-platform/000-plan.md), [`../../docs/interfaces/metadata-cache.md`](../../docs/interfaces/metadata-cache.md) |

## Background

Removing `CachedMediaLibraryProvider` removes obsolete UI/provider ownership,
not the requirement for cached-first browsing and bounded artwork storage. The
new Catalog and existing Kingfisher pipeline already retain recreatable data,
but the application has no unified visibility or user-controlled purge.

## Goals

- Keep cached-first Catalog behavior independent of the removed provider
  decorator.
- Expose one TCA dependency and feature for cache usage and destructive purge.
- Show metadata, artwork, and total cache size in the standard macOS Settings
  window.
- Require explicit confirmation before clearing.
- Clear only recreatable Catalog, legacy metadata, and artwork data.
- Refresh reported usage after a successful clear.
- Preserve Profile/CloudKit state, source configuration, active selection,
  Keychain credentials, playback runtime, and Remote pairing records.

### Non-goals

- Per-item cache deletion or offline download management.
- Clearing authentication/session state.
- Treating Core Data SQLite structural overhead as cached media content.
- Reintroducing `CachedMediaLibraryProvider` or allowing views to own cache IO.

## Design / Approach

1. Extend `CatalogRepository` with value-typed cache statistics and a
   recreatable-data purge operation. Catalog byte usage is the logical stored
   payload size, so an empty Catalog reports zero regardless of SQLite page
   overhead.
2. Keep artwork accounting and clearing in the Kingfisher boundary, including
   memory eviction and asynchronous disk purge.
3. Include the legacy metadata directory in migration cleanup so upgrades do
   not strand data created by `CachedMediaLibraryProvider`.
4. Add `CacheClient` as a TCA dependency that aggregates infrastructure values
   into metadata/artwork/total usage.
5. Add `CacheFeature` with latest-wins usage loading, explicit confirmation,
   clear progress, normalized failures, and post-clear reload.
6. Add a standard SwiftUI `Settings` scene. Views only render state and send
   cache actions.
7. Verify Catalog statistics/purge, reducer success/failure behavior, and the
   full macOS/package suites.

## Alternatives & decisions

- **Rejected: retain `CachedMediaLibraryProvider` for cache management.** It
  combines provider calls, invalidation, and caching and would restore the
  ownership boundary just removed.
- **Rejected: delete the whole Application Support directory.** It contains
  Profile and source state and violates the destructive-action boundary.
- **Rejected: report raw SQLite file size.** Empty SQLite files retain
  structural pages and WAL behavior, so the UI would imply that clearing did
  not work. Logical payload size is stable and testable.
- **Deferred: pluggable per-source offline storage.** Future download caches can
  add another category without changing Profile or Catalog ownership.

## Amendments
