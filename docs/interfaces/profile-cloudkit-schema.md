# Profile and CloudKit Persistence

- **Status:** Implemented; signed multi-device smoke test required for release
- **CloudKit container:** `iCloud.com.samsonlab.cinelark`

The Profile repository is the local-first authority for favorites and playback
state. Provider user state is never queried as the live UI source. It enters the
repository only through an explicit one-time import, and leaves through an
optional durable mirror queue.

Library/detail projections replace provider `UserData` with the active
Profile's state. Continue Watching is built from local playback records; an
empty Profile value renders empty state rather than falling back to Emby or
UHDNow progress.

## Store topology

`NSPersistentCloudKitContainer` loads two Core Data configurations:

| Configuration | Entities | Synchronization |
| --- | --- | --- |
| `Cloud` | `Profile`, `FavoriteState`, `PlaybackState`, `MediaSnapshot`, `ImportMarker` | Private CloudKit database when signed; in-memory in reducer/package tests |
| `Local` | `ProfileSourceRecord`, `ProfileSourceBinding`, `ActiveProfileSelection`, `MirrorQueueEntry` | Device-local only |

The separate media Catalog is another local Core Data store and is not part of
the CloudKit model. Provider tokens and remote credentials live in Keychain.

## Identity and conflict rules

- Favorite and playback records use `{profileID, mediaKey}` identity.
- `ProfileMediaKey` is locator-based in v1, so two sources remain isolated even
  if they report the same external movie ID.
- Incoming cloud state wins by `modifiedAt`, then lexicographic `deviceID` when
  timestamps are equal.
- `MediaSnapshot` carries the minimum display projection needed for favorites
  and resume while the source is offline.
- Active Profile/Source selection is keyed by device ID and never syncs.

## Import and mirror

Import is explicit and idempotent. The provider returns a stable marker and
remote user ID; the repository stores a composite marker scoped to Profile and
Source before reporting success. Repeating the same import returns `false` and
does not rewrite local state.

Outbound mirror is opt-in per `ProfileSourceBinding`. At most one Profile can
own `{sourceID, remoteUserID}` mirroring. Local writes complete first, then a
device-local queue entry records the locator and mutation. Failures increment
the attempt count and use a capped exponential retry scheduled by
`ProfileFeature`; playback and UI remain available.

## Change delivery

The Cloud store enables persistent history and remote-change notifications.
The repository converts notifications and local writes into a bounded
`AsyncStream<ProfileRepositoryChange>` using `bufferingNewest(1)`. TCA converts
each value to an internal action and reloads only repository projections.

## Release verification

Unit tests cover conflict ordering, Profile isolation, local selection/source
placement, import idempotency, and unique mirror ownership. Before release,
perform a signed two-device smoke test for CloudKit schema deployment, offline
writes, merge delivery, and Profile isolation. Unsigned builds cannot validate
the container entitlement.
