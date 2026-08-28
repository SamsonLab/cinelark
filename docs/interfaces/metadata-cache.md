# Cache management

Status: **Accepted implementation**

## 1. Scope and ownership

Cached-first browsing remains a product capability after the retired provider
decorator was removed. The application has two independent, recreatable cache
categories:

| Category | Owner | User-visible size |
| --- | --- | ---: |
| Catalog metadata | `CoreDataCatalogStore` | Logical encoded payload |
| Artwork | Kingfisher | Disk storage size |

`LibraryFeature` and `SearchFeature` read Catalog projections before refreshing
the active Source. TCA stores query identity, item IDs, and presentation
snapshots; it does not own database records or image data.

## 2. Catalog invariants

- Catalog data is local-only and recreatable from a media source.
- Cache identity preserves exact source and provider locators. External content
  IDs do not implicitly merge records.
- Reported metadata size counts encoded values stored by Catalog entities. It
  excludes SQLite pages, indexes, WAL files, and other structural overhead.
- `removeAllCachedData()` removes Catalog items, locators, source records, and
  refresh metadata. It never opens or deletes a Profile/CloudKit store.
- Cached-first delivery is sequential: the cached response is projected before
  the refresh begins, and query identity rejects obsolete responses.

## 3. Artwork invariants

- The Mac app uses a dedicated Kingfisher cache for bounded memory/disk image
  caching, request coalescing, cancellation, and size-aware decoding.
- Artwork usage reports disk bytes. Clearing also evicts memory entries.
- Authentication tokens are supplied by an authenticated request adapter; they
  never enter image URLs or cache keys.

## 4. Retired provider artifacts

The former provider cache directory at
`Application Support/CineLark/MetadataCache` is not an application cache or a
fallback read path. At startup, `LegacyProviderArtifacts` performs a
best-effort, idempotent removal of that exact directory. The cleanup validates
the terminal path components before deletion and is intentionally absent from
Settings accounting.

The retired provider/session protocols, JSON Keychain session decoder, metadata
cache implementation, and cache decorator are not part of the production
package graph. Future Sources must normalize through Catalog instead of adding a
parallel metadata cache.

## 5. User-controlled purge

The macOS Settings window displays metadata, artwork, and total cache usage.
Clearing requires confirmation and removes only those recreatable categories.
Profiles, favorites, playback progress, source configuration, active selection,
Keychain credentials, playback runtime, and Remote pairing records are outside
the cache boundary.

Before deletion, `CacheFeature` delegates to `AppFeature`. The parent cancels
Library and Search effects that may write Catalog data and removes detail paths
whose projections depend on that data. Only then does `CacheClient` clear the
independent infrastructure stores and refresh usage.

Catalog and artwork deletion are attempted independently; failures are
aggregated and displayed. A later size refresh reflects any data that remains.

## 6. Security exclusions

The following values must never enter metadata or artwork caches:

- credentials or provider session tokens
- tokenized/signed playback or download URLs
- playback descriptors
- bridge pairing credentials
- Remote credentials

Artwork cache keys use Source ID, provider item ID, artwork kind, and a fallback
URL stripped of user info, query, and fragment. Authorization is resolved after
a cache miss and attached only to the download request, so cached artwork can be
used offline without persisting plugin headers or tokens.

Playback and download descriptors always bypass caching and are resolved just
in time.
