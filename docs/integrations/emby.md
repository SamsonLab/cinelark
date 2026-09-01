# Emby Integration

- **Status:** Implemented v1
- **Plugin ID:** `com.samsonlab.cinelark.emby`
- **Non-goals:** Emby Connect, server transcoding, Live TV, music, and complete offline download

## Setup and authentication

The setup flow accepts a manual URL, including a reverse-proxy base path, or
discovers servers by broadcasting `who is EmbyServer?` over UDP port 7359.
Scheme-less public hosts default to HTTPS; localhost, `.local`, private/link-
local IP literals, and IPv6 local addresses default to HTTP. Manual URLs accept
only HTTP(S) with a host and reject embedded credentials, query items, and
fragments. Ports and reverse-proxy paths are preserved, and the normalized URL
is persisted after validation. A candidate is verified through
`System/Info/Public`; its returned server ID is the stable
`SourceInstanceIdentity` component.

Setup currently advertises username/password authentication only. Authentication
uses a stable device ID and `X-Emby-Authorization`. The selected
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

Movie, series, and episode are distinct normalized item kinds. Episodes remain
children of series in navigation, but resume import keeps each episode's exact
provider item identity so local Profile facts and insights are not attributed
to the containing series.

Summary requests explicitly include original title and genres. Genre names are
trimmed and deduplicated in provider order, with a deterministic local slug and
presentation ID; that derived ID is not an Emby genre identity and is never
used for cross-source matching. `ChildCount` becomes a season count only for a
series. `UserData.LastPlayedDate` accepts whole- or fractional-second ISO-8601
instants.

Provider playback timestamps remain non-authoritative during ordinary browsing.
Only the explicit remote-import action copies last-played state and genre
evidence into the active CineLark Profile. A genre-only import retains any
director or cast dimensions already captured from detail or playback.

Emby pagination advances `StartIndex` by the number of raw provider items
consumed, not by the number of normalized items emitted. An empty page before
`TotalRecordCount` or a repeated cursor is treated as an invalid response. This
keeps an unsupported provider item from stalling browse or remote-state import.

Poster, backdrop, logo, season, episode, and person image metadata are mapped to
provider-neutral URLs. The artwork capability can also produce the required
authorization header. On a Kingfisher cache miss, the macOS image pipeline
resolves that capability just in time and attaches the header to the ephemeral
request. Headers never enter SwiftUI/TCA state, Catalog/Profile values, URLs, or
cache keys. Capability-resolved artwork rejects credential-bearing URLs,
cross-origin header forwarding, and cross-origin redirects. Safe same-origin
redirects are allowed for immutable image delivery; an authenticated CDN still
needs an explicit credential-scope contract rather than relaxed validation.

## Playback semantics

`PlaybackInfo` must expose a media source supported by direct play or direct
stream. Otherwise the plugin returns an unsupported domain failure and does not
launch IINA. Playback descriptors are ephemeral and carry authorization headers
separately from the URL. Absolute, root-relative, and reverse-proxy-relative
direct-stream references are normalized to the configured server origin.
Fragments and user info are removed; cross-origin and non-HTTP(S) references
are rejected before an account header can be forwarded. Provider-issued query
capabilities remain on the ephemeral playback URL for IINA compatibility, but
must not enter presentation state, persistence, caches, or diagnostics.
For every playable source, a non-empty `DirectStreamUrl` is authoritative even
when the source also advertises direct play. CineLark uses the canonical
`Videos/{itemId}/stream?static=true&MediaSourceId={sourceId}` route only when
the provider omits that target. Playback authenticates with the player-safe
`X-Emby-Token` header. If a same-origin reference supplies a provider `token`,
CineLark also forwards its validated raw value as the ephemeral `Authorization`
header without removing the provider capability from the URL. The player bridge
applies these values as file-local native headers immediately before opening
the stream. Credentials do not enter logs, reducer state, Catalog, Profile, or
caches.

Started is reported after the engine activates the item. Progress is sent on
the reducer-controlled cadence and after interactions. Stopped always closes
the session; only a natural EOF produces local played state automatically. An
account-bound ordered reporter serializes the three wire submissions even when
the service actor suspends for HTTP. Check-ins remain best-effort and are not
replayed after an ambiguous failure.

Emby response normalization maps authentication failures, rate limiting,
transient service failures, and permanent request rejection into stable domain
failures without retaining response bodies. Optional Profile mirror delivery
retries only the safely idempotent desired-state assignments. It honors a
clamped delta-seconds `Retry-After` value or uses bounded exponential backoff;
permanent failures stop retrying and never roll back CineLark's local state.

## Validation

Synthetic real-shape fixture tests cover reverse-proxy URL preservation, UDP
response parsing and deduplication, raw offset cursor mapping, episode resume
identity, metadata normalization, series counts, content/detail hierarchy,
image metadata, same-origin ephemeral playback capabilities, remote import/mirror
endpoints, exact-user enforcement, and direct playback headers. Registry and
TCA tests additionally cover legacy alias ownership, explicit reconnect state,
identity preservation, successful cleanup, non-destructive validation failure,
explicit Profile import, episode playback identity, response retry
classification, permanent mirror failure, and suspended check-in ordering.
Private Postman responses and live account data are never repository fixtures.

The [`CineLark Emby Postman kit`](../../tools/postman/README.md) provides the
same implemented surface as an importable collection, real-server environment
template, and loopback-only deterministic mock for manual contract validation.
