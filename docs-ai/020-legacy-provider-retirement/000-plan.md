# 020 — Legacy Provider Retirement: Plan

| | |
| --- | --- |
| **Status** | Implemented and verified |
| **Anchor date** | 2026-08-28 |
| **Primary refs** | Pending |
| **Related** | [TCA application architecture](../010-tca-application-architecture/000-plan.md), [Cache management](../012-cache-management/000-plan.md), [Emby source unification](../016-emby-source-unification/000-plan.md) |

## Background

The macOS application no longer reads `MediaLibraryProvider` or
`CachedMediaLibraryProvider`; TCA Features use the media-source platform and
Core Data Catalog. The retired compatibility surface still leaves provider
session models, protocols, a JSON Keychain store, an independent metadata cache,
and tests in the production package graph.

Keeping a second unused caching and authentication abstraction obscures the
current ownership model and makes cache Settings report data that no runtime can
recreate.

## Goals

- Remove `MediaLibraryProvider`, `ProviderSessionStore`, provider credentials,
  provider sessions, `CachedMediaLibraryProvider`, and their tests.
- Remove the unused persistent metadata cache and its generic cache contracts.
- Keep `CineLarkPersistence` focused on Keychain secret infrastructure.
- Preserve safe cleanup of the retired metadata directory and UHDNow session
  Keychain record without retaining the old domain types.
- Make Cache Settings report and clear only active Catalog and artwork caches.
- Replace legacy cache tests with a narrow migration-artifact cleanup test.
- Verify no source or test target references the retired provider surface.

### Non-goals

- Removing Catalog or Kingfisher caching.
- Deleting Profile, source configuration, artwork, or current Emby tokens.
- Migrating private-facade item IDs to standard Emby IDs.
- Renaming `CineLarkPersistence`; it remains the Keychain infrastructure target.

## Design / Approach

`LegacyProviderArtifacts` owns exactly one filesystem migration concern: remove
the historical `Application Support/CineLark/MetadataCache` directory. Its API
accepts an explicit directory in tests and validates that only that resolved
directory is removed. The composition root invokes it best-effort at startup.

The historical provider session was stored as a generic-password record under
service `com.samsonlab.cinelark.provider`. `KeychainSecretStore` can delete that
record by service/account without decoding the old JSON `ProviderSession`, so
`KeychainSessionStore` and the session model are unnecessary.

`CacheClient` aggregates only:

- Core Data Catalog logical cache usage and purge;
- Kingfisher artwork disk usage and purge.

The legacy directory is a migration artifact, not an active cache category and
therefore is not included in ongoing user-visible usage.

## Alternatives & decisions

- **Retain the generic metadata cache for future protocols:** rejected because
  future Sources must normalize through Catalog instead of restoring parallel
  provider ownership.
- **Leave the old types deprecated:** rejected because no compatibility consumer
  remains and deprecation would prolong duplicate architecture.
- **Delete the legacy directory from `CacheClient`:** rejected because migration
  cleanup should happen independently of whether a user opens Settings or clears
  current caches.
- **Keep `KeychainSessionStore` only for deletion:** rejected because generic
  Keychain deletion does not require decoding the retired session payload.

## Amendments

- None.
