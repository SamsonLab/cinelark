# Personal Viewing Memory and CloudKit Persistence

- **Status:** Local-first implementation complete; signed two-device convergence execution pending
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
| `ProfileID` | One durable viewing history | Cloud | Fixed canonical Personal identity within each iCloud private database |
| `SourceID` | One configured media source | Local configuration | Stable app identity; connection details and credentials do not enter CloudKit |
| `RemoteUserID` | Provider account within a Source | Local binding | Never substitutes for `ProfileID` |
| `ContentKey` | Optional canonical content evidence | Cloud snapshot/Catalog | Supports future cross-source matching; never replaces a locator |
| `MediaLocatorID` | Exact provider item/path | Cloud snapshot/Local Catalog | Required to play or mirror a provider mutation |

The active `{profileID, sourceID}` selection is keyed by `ClientID` and remains
local. Bootstrap always repairs its Profile component to `.personal`; Source
selection remains device-local. This never changes the client identity.

## Store topology

`NSPersistentCloudKitContainer` loads two Core Data configurations:

| Configuration | Entities | Synchronization |
| --- | --- | --- |
| `Cloud` | `Profile`, `FavoriteState`, `PlaybackState`, `MediaSnapshot`, `ImportMarker`, `ProfileMergeMarker`, `DeviceRecord`, `ViewingSession`, `ProfilePlaybackEvent`; future `InsightSnapshot` | Private CloudKit database when signed in; in-memory in package/reducer tests |
| `Local` | `ProfileSourceRecord`, `ProfileSourceBinding`, `ActiveProfileSelection`, `MirrorQueueEntry`, `MutationClockState`, `ProvisionalProfile`, `ProvisionalFavoriteState`, `ProvisionalPlaybackState`, `ProvisionalMediaSnapshot`, `ProvisionalImportMarker`, `ProvisionalDeviceRecord`, `ProvisionalViewingSession`, `ProvisionalPlaybackEvent` | Device-local only |

The media Catalog is a separate local Core Data store. Provider tokens and
remote credentials remain in Keychain.

## Bootstrap state machine

A fresh installation creates `ClientID` and a provisional local Personal
Profile with the canonical `ProfileID` before CloudKit availability is known.
It is usable immediately but is not published merely because the local cloud
replica is temporarily empty.

| Cloud state | Profile state | Resolution |
| --- | --- | --- |
| Unavailable | Canonical provisional | Continue local-only and retry discovery later |
| Initial import pending | Canonical provisional | Continue locally; show checking status |
| Confirmed empty | Canonical provisional | Promote it to Cloud |
| Available | Canonical cloud Profile | Normal synchronization |
| Available | Legacy Profile IDs | Automatically consolidate them into `.personal` |

Merge is idempotent. A `ProfileMergeMarker` records the operation, source, and
target. Cloud-to-cloud merge retains the source as a hidden tombstone-like
record. Consolidation copies facts and import markers with their original
mutation stamps, migrates local bindings, selections, and mirror-queue entries,
and removes a provisional graph only after the Cloud-store save succeeds.

While initial import remains pending, the app restores configured Source
runtimes against the canonical provisional graph without a blocking choice.
A later successful import invalidates bootstrap and automatically consolidates
the graph into the same identity.

## Synchronization health

Settings projects CloudKit account and transport evidence into five states:

| State | Meaning |
| --- | --- |
| Local Only | The iCloud account is unavailable; Profile facts remain usable locally |
| Checking iCloud | Account is available but initial import readiness is not confirmed |
| Synchronizing | A persistent-container setup, import, or export event is active |
| Available | iCloud is available and no active or failed event is observed |
| Needs Attention | The latest completed transport event failed; local facts remain authoritative |

The status includes the latest successful persistent-container event time when
available. Event-history requests set `affectedStores` to the Cloud store so the
Local configuration never receives an unsupported CloudKit event request.
Transport notifications become repository invalidations; only the value-typed
status enters TCA State.

**Recheck iCloud** refreshes account, readiness, and event projections. It does
not claim to force synchronization because `NSPersistentCloudKitContainer`
owns scheduling and automatic retry.

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
| Profile media metadata | The snapshot stamp selects the incoming record; each non-empty incoming genre/director/cast dimension replaces that dimension, while missing or empty dimensions retain existing evidence |
| `MediaSnapshot` | Preserve historical identity; the latest stamped snapshot is the presentation projection |
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
`{sourceID, remoteUserID}` mirror. The durable queue retries only provider
failures classified as transient, honors bounded provider delay guidance, and
uses exponential backoff otherwise. Permanent rejection removes the delivery
entry and surfaces recovery guidance without rolling back the local Profile.

## Current implementation boundary

Implemented and covered by package tests:

- typed client/Profile identity;
- persistent hybrid logical mutation-clock entity;
- mutation-stamp conflict ordering with legacy fallback;
- Profile manifests over current snapshot/projection data;
- stable canonical Personal Profile identity across devices;
- idempotent Profile merge markers and non-destructive source retention;
- tombstoned Profile deletion.
- Local-store provisional Profile, favorite, playback, media-snapshot, and
  import-marker routing;
- CloudKit account status and completed initial-import readiness checks;
- idempotent provisional promotion and merge;
- automatic legacy/provisional consolidation and the TCA application-readiness barrier.
- Cloud and provisional `DeviceRecord`, `ViewingSession`, and
  `ProfilePlaybackEvent` persistence;
- atomic playback projection/session/event/device writes before independent
  provider reporting;
- idempotent event insertion, mutation-ordered session updates, and fact
  preservation through provisional promotion and Profile merge;
- Profile manifest session/watch-time summaries and friendly last-device
  projection from durable facts.
- optional genre/director/cast evidence in media snapshots with legacy payload
  compatibility and dimension-complete merging for partial imports;
- rebuildable month, quarter, year, and all-time Insights projections over
  Profile-owned facts. Derived snapshots remain outside Core Data and CloudKit.
- exact-locator cached enrichment for missing snapshot genres/artwork, persisted
  with the mutation clock without storing recommendation projections;
- automatic pending-import local-first continuation through the application
  readiness barrier;
- Settings sync health over account status plus setup/import/export events.
- privacy-preserving Profile fact audits and a signed-app convergence harness;
  see the [CloudKit convergence runbook](../runbooks/cloudkit-convergence-validation.md).

Still required before treating multi-device sync as release-ready:

- execute the signed two-device matrix covering delayed initial import, offline
  writes, concurrent conflict, merge, tombstones, reinstall, and account
  transition behavior. Harness availability is not evidence of convergence.
