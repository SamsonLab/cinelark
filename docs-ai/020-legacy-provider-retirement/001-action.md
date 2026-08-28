# 020 — Legacy Provider Retirement: Action

| | |
| --- | --- |
| **Status** | Implemented and verified |
| **Date** | 2026-08-28 |
| **Scope** | Retired provider/session/cache removal and narrow upgrade cleanup |

## Implemented

- Removed `MediaLibraryProvider`, `ProviderSessionStore`, provider credentials,
  provider sessions, `CachedMediaLibraryProvider`, `KeychainSessionStore`, the
  generic metadata cache contracts, and their obsolete tests.
- Removed the unused Domain dependency from `CineLarkPersistence`; the target
  now owns only active Keychain infrastructure and migration cleanup.
- Added `LegacyProviderArtifacts`, which validates and removes only the former
  `Application Support/CineLark/MetadataCache` directory. Startup invokes this
  idempotent cleanup on a best-effort path.
- Reused `KeychainSecretStore` to remove the retired UHDNow generic-password
  record after a successful canonical Emby reconnect without decoding the old
  session payload.
- Reduced `CacheClient` and Settings accounting to the two active recreatable
  stores: Catalog metadata and Kingfisher artwork.
- Replaced the stale provider interface with a documentation tombstone so
  historical links remain valid while all current integration guidance points
  to the media-source platform and Catalog contracts.

## Verification

- TDD red: `swift test --filter LegacyProviderArtifactsTests` initially failed
  because the cleanup type and error did not exist.
- TDD green: the same focused suite passes both path-safety and idempotency
  cases.
- `swift test` passes 57 tests across the package suites.
- Unsigned `xcodebuild ... test` passes 32 Swift Testing tests across 13 suites
  and 6 XCTest cases.
- Repository search finds no production or test references to the retired
  provider/session/cache types.
- `git diff --check` passes.

## Deviations from the plan

- The interface document remains as a short retired-contract tombstone instead
  of being deleted because older docs-ai records link to it. It contains no
  executable contract or compatibility recommendation.

## TCA learning review

No new `TCA-learn.md` entry was added. This milestone removed obsolete
infrastructure ownership; the reusable Feature ownership and cache-clear
coordination lessons are already captured by `L009` and `L012`.

## Follow-up

- Future media protocols must implement capability-based Sources and normalize
  through Catalog; they must not restore a parallel provider/cache abstraction.
