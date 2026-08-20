# Metadata cache

Status: **Accepted implementation**

## 1. Scope

`CineLarkPersistence` provides a provider-neutral, actor-isolated metadata cache
and a `CachedMediaLibraryProvider` read-through decorator. The cache persists
recreatable domain metadata across app launches while keeping the provider API
authoritative.

Artwork is intentionally outside this cache. The Mac app uses Kingfisher for
bounded memory/disk image caching, request coalescing, cancellation, and
size-aware decoding.

## 2. Storage invariants

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

The cache assumes one in-process `PersistentMetadataCache` writer for a storage
directory. It is not an inter-process database.

## 3. Read behavior

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

## 4. Invalidation and account boundaries

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

## 5. Security exclusions

The following values must never enter metadata or artwork caches:

- credentials or provider session tokens
- tokenized/signed playback or download URLs
- playback descriptors
- bridge pairing credentials
- Remote credentials

`playbackURL(for:)` and `downloadURL(for:)` always bypass
`CachedMediaLibraryProvider` caching and are resolved just in time.
