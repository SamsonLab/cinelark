# Emby Integration

- **Status:** Implemented v1
- **Plugin ID:** `com.samsonlab.cinelark.emby`
- **Non-goals:** Emby Connect, server transcoding, Live TV, music, and complete offline download

## Setup and authentication

The setup flow accepts a manual URL, including a reverse-proxy base path, or
discovers servers by broadcasting `who is EmbyServer?` over UDP port 7359. A
candidate is verified through `System/Info/Public`; its returned server ID is
the stable `SourceInstanceIdentity` component.

Authentication uses a stable device ID and `X-Emby-Authorization`. The selected
remote user ID is stored in `SourceConfiguration`; the access token is stored
under the Source ID in Keychain. Tokens are never appended to metadata,
artwork, or playback URLs.

UHDNow subscriptions use this same setup and protocol surface; there is no
separate UHDNow plugin. Persisted sources created by the retired private adapter
are shown as **Reconnect as Emby**. CineLark suggests the old URL with a trailing
`/api/v1` removed, but `System/Info/Public` verification and a fresh Emby login
are mandatory. A successful reconnect preserves `SourceID` and local Profile
history, then removes the legacy Keychain session. Provider item IDs are not
guessed or remapped if the old facade and Emby expose different identities.

## Implemented mapping

| CineLark capability | Emby surface |
| --- | --- |
| Collections | `Users/{user}/Views` |
| Browse/search | `Users/{user}/Items` with opaque CineLark cursor mapped to `StartIndex` |
| Latest/resume | `Users/{user}/Items/Latest`, `Users/{user}/Items/Resume` |
| Detail and people | Item detail with `People` and provider IDs |
| Seasons/episodes | `Shows/{series}/Seasons`, `Shows/{series}/Episodes` |
| Person/works | person item plus `PersonIds` item query |
| Playback | `Items/{item}/PlaybackInfo`, direct play/direct stream only |
| Check-ins | `Sessions/Playing`, `Sessions/Playing/Progress`, `Sessions/Playing/Stopped` |
| Import | paged favorites plus resume state |
| Mirror | FavoriteItems, PlayedItems, and progress endpoints for the exact configured user |

Poster, backdrop, logo, season, episode, and person image metadata are mapped to
provider-neutral URLs. The artwork capability can also produce the required
authorization header. The current URL-only SwiftUI image surface does not yet
consume that header, so authenticated artwork delivery is the remaining UI
integration gap; putting the token in the URL is intentionally forbidden.

## Playback semantics

`PlaybackInfo` must expose a media source supported by direct play or direct
stream. Otherwise the plugin returns an unsupported domain failure and does not
launch IINA. Playback descriptors are ephemeral and carry authorization headers
separately from the URL.

Started is reported after the engine activates the item. Progress is sent on
the reducer-controlled cadence and after interactions. Stopped always closes
the session; only a natural EOF produces local played state automatically.

## Validation

Fixture tests cover reverse-proxy URL preservation, UDP response parsing and
deduplication, offset cursor mapping, content/detail hierarchy, image metadata,
secret-free URLs, remote import/mirror endpoints, exact-user enforcement, and
direct playback headers. Registry and TCA tests additionally cover legacy alias
ownership, explicit reconnect state, identity preservation, successful cleanup,
and non-destructive validation failure.

The [`CineLark Emby Postman kit`](../../tools/postman/README.md) provides the
same implemented surface as an importable collection, real-server environment
template, and loopback-only deterministic mock for manual contract validation.
