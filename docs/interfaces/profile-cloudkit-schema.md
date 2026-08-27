# Personal Viewing Memory and CloudKit Persistence

- **Status:** Local-first bootstrap and Profile resolution implemented; signed multi-device validation pending
- **CloudKit container:** `iCloud.com.samsonlab.cinelark`
- **Normative decision:** [`../decisions/0011-personal-viewing-memory.md`](../decisions/0011-personal-viewing-memory.md)

CineLark owns a source-independent personal viewing memory. The local Profile
repository is the UI authority for favorites, progress, history, and later
insights. Emby user data remains a separate remote record: it can be imported
explicitly and mirrored outbound through standard Emby APIs, but it never
becomes an implicit fallback for the active Profile.

## Identity layers

| Identity | Scope | Persistence | Rule |
| --- | --- | --- | --- |
| `ClientID` | One CineLark installation | Local preferences | Generated before network access; used as Emby `DeviceId`; never replaced by Profile resolution |
| `DeviceRecordID` | Synced device presentation record | Cloud | Records device name and last-seen activity without containing credentials |
| `ProfileID` | One durable viewing history | Cloud | Multiple Profiles may coexist in one iCloud private database |
| `SourceID` | One configured media source | Local configuration | Stable app identity; connection details and credentials do not enter CloudKit |
| `RemoteUserID` | Provider account within a Source | Local binding | Never substitutes for `ProfileID` |
| `ContentKey` | Optional canonical content evidence | Cloud snapshot/Catalog | Supports future cross-source matching; never replaces a locator |
| `MediaLocatorID` | Exact provider item/path | Cloud snapshot/Local Catalog | Required to play or mirror a provider mutation |

The active `{profileID, sourceID}` selection is keyed by `ClientID` and remains
local. Choosing or merging a cloud Profile changes this binding, not the
client identity.

## Store topology

`NSPersistentCloudKitContainer` loads two Core Data configurations:

| Configuration | Entities | Synchronization |
| --- | --- | --- |
| `Cloud` | `Profile`, `FavoriteState`, `PlaybackState`, `MediaSnapshot`, `ImportMarker`, `ProfileMergeMarker`, `DeviceRecord`, `ViewingSession`, `ProfilePlaybackEvent`; future `InsightSnapshot` | Private CloudKit database when signed in; in-memory in package/reducer tests |
| `Local` | `ProfileSourceRecord`, `ProfileSourceBinding`, `ActiveProfileSelection`, `MirrorQueueEntry`, `MutationClockState`, `ProvisionalProfile`, `ProvisionalFavoriteState`, `ProvisionalPlaybackState`, `ProvisionalMediaSnapshot`, `ProvisionalImportMarker`, `ProvisionalDeviceRecord`, `ProvisionalViewingSession`, `ProvisionalPlaybackEvent` | Device-local only |

The media Catalog is a separate local Core Data store. Provider tokens and
remote credentials remain in Keychain.

## Bootstrap state machine

A fresh installation creates `ClientID` and a provisional local Profile before
CloudKit availability is known. The provisional Profile must not be published
merely because the local cloud replica is temporarily empty.

| Cloud state | Profile state | Resolution |
| --- | --- | --- |
| Unavailable | Any | Continue local-only and retry discovery later |
| Initial import pending | Any | Keep provisional local; show checking state |
| Confirmed empty | Provisional only | Promote provisional Profile to Cloud |
| Available | Matching `ProfileID` | Normal synchronization |
| Available | Different Profiles | Present attach/merge/keep-separate choice |

The choice surface presents Profile name, recent activity, last device, title
and favorite counts, session count, and total watch time. These manifest values
are eventually consistent presentation summaries; durable viewing facts remain
the rebuildable source of truth.

Merge is idempotent. A `ProfileMergeMarker` records the operation, source, and
target. Cloud-to-cloud merge retains the source as a hidden tombstone-like
record. Provisional-to-cloud merge copies facts and import markers with their
original mutation stamps, migrates local bindings, and removes the local
provisional graph only after the Cloud-store save succeeds.

## Time and conflict ordering

All stored `Date` values represent absolute instants. UI formatting applies the
current locale and time zone. A UTC date alone is not a conflict clock because
device time can move backward.

Mutable records use `MutationStamp`:

```text
physicalMillisecondsUTC + logicalCounter + clientID
```

The local `MutationClockState` guarantees that each issued stamp is greater than
the previous stamp even when wall time is equal or decreases. The client ID is
the deterministic final tie-breaker. Legacy records without a stamp fall back
to `{modifiedAt, deviceID}` during migration.

| Data | Merge rule |
| --- | --- |
| `ViewingSession` | Stable session ID; higher mutation stamp updates the rebuildable aggregate |
| `ProfilePlaybackEvent` | Immutable union by stable event ID |
| `PlaybackState` | Materialized projection; higher mutation stamp wins until event rebuilding is implemented |
| `FavoriteState`, `RatingState` | Explicit value/tombstone with higher mutation stamp |
| Profile metadata | Field-level mutation in the eventual schema; record-level stamp in the current slice |
| `MediaSnapshot` | Preserve historical value; latest snapshot is a presentation projection |
| Deletion | Tombstone first; physical cleanup only after a validated retention boundary |

CloudKit record change tags and server `modificationDate` remain transport
metadata. They detect conflicts but do not define CineLark's domain merge rule.

## Provider-state boundary

Every playback lifecycle has two independent outputs:

1. Append or update CineLark viewing memory locally, then allow CloudKit to
   mirror it asynchronously.
2. Enqueue standard provider reporting for the bound remote user.

Local persistence is mandatory for product continuity. Provider reporting is
ordered and best-effort; failure never rolls back local state. Emby reporting
uses `Started`, periodic/interactive `Progress`, and `Stopped`. UHDNow
subscriptions use that standard Emby path and do not own a separate plugin or
Profile model. Legacy private-adapter sources require explicit reconnect while
preserving their existing local `SourceID`.

Remote import remains explicit and idempotent. Outbound favorite/playback mirror
remains opt-in per binding, with at most one local Profile owning a given
`{sourceID, remoteUserID}` mirror.

## Current implementation boundary

Implemented and covered by package tests:

- typed client/Profile identity;
- persistent hybrid logical mutation-clock entity;
- mutation-stamp conflict ordering with legacy fallback;
- Profile manifests over current snapshot/projection data;
- bootstrap resolution as a pure contract;
- idempotent Profile merge markers and non-destructive source retention;
- tombstoned Profile deletion.
- Local-store provisional Profile, favorite, playback, media-snapshot, and
  import-marker routing;
- CloudKit account status and completed initial-import readiness checks;
- idempotent provisional promotion and merge;
- TCA application-readiness barrier and root Profile-resolution surface.
- Cloud and provisional `DeviceRecord`, `ViewingSession`, and
  `ProfilePlaybackEvent` persistence;
- atomic playback projection/session/event/device writes before independent
  provider reporting;
- idempotent event insertion, mutation-ordered session updates, and fact
  preservation through provisional promotion and Profile merge;
- Profile manifest session/watch-time summaries and friendly last-device
  projection from durable facts.
- optional genre/director/cast evidence in media snapshots with legacy payload
  compatibility;
- rebuildable month, quarter, year, and all-time Insights projections over
  Profile-owned facts. Derived snapshots remain outside Core Data and CloudKit.

Still required before treating multi-device sync as release-ready:

- signed two-device tests covering offline creation, delayed initial import,
  merge, tombstones, and reinstall behavior.
