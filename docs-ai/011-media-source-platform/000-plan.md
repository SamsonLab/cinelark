# 011 — Media Source Platform: Plan

| | |
| --- | --- |
| **Status** | Active — contracts, catalog core, UHDNow adapter, and Emby transport slice implemented |
| **Anchor date** | 2026-08-26 |
| **Primary refs** | [`001-action.md`](001-action.md), [`../../docs/interfaces/media-source-platform.md`](../../docs/interfaces/media-source-platform.md) |
| **Related** | [`../010-tca-application-architecture/000-plan.md`](../010-tca-application-architecture/000-plan.md), [`../../docs/interfaces/media-library-provider.md`](../../docs/interfaces/media-library-provider.md), [`../../docs/product-spec.md`](../../docs/product-spec.md) |

## Background

The app composition root currently constructs one UHDNow provider, while the
domain protocol assumes that catalog, authentication, remote favorites, and
remote progress are always supplied by the same service. An Infuse-class client
must also support servers and file protocols whose capabilities differ
substantially.

## Goals

- Add a statically registered, capability-based media plugin API.
- Distinguish plugin type, configured source, authenticated account, catalog
  item, physical/provider locator, and optional canonical content identity.
- Establish a local normalized catalog that can later aggregate multiple
  sources without changing feature queries.
- Keep profile favorites and progress local-first and independently syncable.
- Add a standard Emby source while preserving UHDNow behavior.

### Non-goals

- Runtime third-party code loading.
- Multi-source aggregation UI in the first implementation.
- Emby Connect, server transcoding, Live TV, music, or managed offline media.
- Cross-Apple-ID profile sharing.

## Design / Approach

1. A composition-root registry owns SwiftPM plugin factories keyed by stable
   plugin IDs.
2. Each configured source produces a runtime composed from optional discovery,
   authentication, browse, search, artwork, playback, download, change-feed,
   import, and mirror clients.
3. Calls use async functions for cold requests and bounded async sequences for
   hot event streams. Plugin contracts never expose UI or TCA types.
4. Queries use source scopes and opaque cursors so server offsets, page numbers,
   and filesystem enumeration share one interface.
5. A local Core Data catalog stores normalized items and one-to-many locators.
   It is rebuildable and remains outside iCloud.
6. Profile, favorite, and playback records use a CloudKit-backed Core Data
   configuration; source configuration, bindings, mirror queues, and catalog
   data use a local configuration. Secrets remain in Keychain.
7. UHDNow is adapted first, followed by Emby discovery, authentication,
   library mapping, playback resolution, and check-ins.

## Alternatives & decisions

- A single complete provider protocol was rejected because file and server
  sources would need unrelated stub behavior.
- Separate unrelated server and filesystem application models were rejected
  because they duplicate search, catalog, navigation, and playback pipelines.
- Dynamic XPC or process plugins were deferred because built-in commercial
  protocol support does not justify the signing and lifecycle cost yet.
- Immediate multi-source aggregation was deferred; the catalog and source-set
  query shapes retain the necessary extension points.

## Amendments

- Updated 2026-08-26: Continue through the Cloud/Local profile repository,
  persisted source bootstrap, Emby LAN setup, complete v1 content mapping, and
  Catalog-only UI reads — see
  [`002-profile-emby-and-catalog-completion.md`](002-profile-emby-and-catalog-completion.md).
- Updated 2026-08-27: Profile identity, first-install CloudKit resolution, and
  conflict ordering are replaced by the personal viewing-memory model — see
  [`../014-viewing-identity-and-sync/000-plan.md`](../014-viewing-identity-and-sync/000-plan.md).
