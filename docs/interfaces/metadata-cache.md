# Cache management

Status: **Accepted implementation**

## 1. Scope and ownership

Cached-first browsing remains a product capability after UI ownership moved
away from `CachedMediaLibraryProvider`. The current application cache has three
independent infrastructure categories:

| Category | Owner | User-visible size |
| --- | --- | ---: |
| Catalog metadata | `CoreDataCatalogStore` | Logical encoded payload |
| Artwork | Kingfisher | Disk storage size |
| Legacy metadata | `PersistentMetadataCache` | Encoded entry size |

`LibraryFeature` reads Catalog projections first and then performs a source
refresh. TCA stores only query identity, item IDs, and presentation snapshots;
it does not own database records or image data. The legacy metadata cache is no
longer an application read path and is included only so upgrades can measure
and remove data created by the former provider decorator.

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
- Authentication tokens must be supplied by an authenticated request adapter;
  they must not be embedded in image URLs or cache keys.

## 4. Legacy metadata compatibility

- Metadata lives under `Application Support/CineLark/MetadataCache`.
- A versioned manifest indexes individually encoded JSON entries.
- Cache keys are stored only as SHA-256-derived file identifiers; search terms
  and provider parameters are not written into file names.
- Entry and manifest writes are atomic. Corrupt or missing entries are removed
  and treated as cache misses.
- The default limits are 2,000 entries and 128 MiB.
- Least-recently-used entries are evicted when either limit is exceeded.
- Expired entries are retained for at most 30 days as outage fallback data.
- A schema-version mismatch clears the recreatable store instead of attempting
  unsafe model migration.

The store assumes one in-process `PersistentMetadataCache` writer for a storage
directory. It is not an inter-process database. New application reads use the
Catalog; these rules are retained for safe cleanup and package compatibility.

### Historical read behavior

Each provider capability has an explicit freshness TTL. Defaults are:

| Resource | Fresh TTL |
| --- | ---: |
| Hot library | 15 minutes |
| Collection definitions | 6 hours |
| Collection items | 1 hour |
| Search results | 10 minutes |
| Movie/series detail | 24 hours |
| Seasons | 6 hours |
| Episodes and assets | 1 hour |
| Person detail | 24 hours |
| Person works | 6 hours |
| Favorites and playback shelf | 1 minute |

A fresh value is returned without a network request. An expired value triggers
a provider request and is replaced on success. Stale data may be returned only
for network outages, rate limiting, provider unavailability, or an undecodable
provider response. Authentication, authorization, not-found, cancellation, and
unsupported-capability errors never fall back to stale data.

### Historical invalidation and account boundaries

- Successful favorite and playback-state mutations invalidate related tagged
  entries.
- Sign-in, sign-out, and failure to restore a valid provider session clear the
  metadata cache.
- Cache namespaces include the provider contract version.
- Capacity and stale-retention maintenance runs during session restoration and
  after writes.

These rules prevent user-specific playback/favorite state from crossing account
boundaries while retaining metadata through normal launches for one valid
session.

## 5. User-controlled purge

The macOS Settings window displays metadata, artwork, and total on-disk cache
usage. Clearing requires confirmation and removes only recreatable categories.
Profiles, favorites, playback progress, source configuration, active selection,
Keychain credentials, playback runtime, and Remote pairing records are outside
the cache boundary.

Before deletion, `CacheFeature` delegates to `AppFeature`. The parent cancels
Library and Search effects that may write Catalog data and removes detail paths
whose projections depend on that data. Only then does `CacheClient` clear the
independent infrastructure stores and refresh usage.

Individual cache categories attempt deletion independently; failures are
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
