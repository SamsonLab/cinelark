# Media Source Platform

The platform is a compile-time SwiftPM plugin system. A plugin factory declares a
stable ID, contract version, roles, setup/authentication modes, and a structured
capability descriptor. The composition root explicitly registers factories;
third-party dynamic code is not loaded.

## Identity

- `PluginID` identifies an implementation.
- `SourceID` identifies a user-configured source across devices.
- `SourceInstanceIdentity` combines plugin kind with a verified server identity.
- `MediaLocatorID` identifies one provider item within one source.
- `CatalogItemID` identifies normalized local metadata.
- `ContentKey` is matching evidence and never replaces a locator.

The Core Data catalog supports multiple locators for one catalog item. It does
not merge items merely because TMDB or IMDb keys match.

`MediaKind` describes the normalized item identity, not a navigation section.
The current kinds are movie, series, and episode. The v1 UI still exposes only
movie and series as top-level library categories; episodes enter the catalog
and Profile projections through hierarchy and resume results.

## Calls and streams

Cold queries and commands are `async throws`. Snapshot streams use
`AsyncStream`/`AsyncThrowingStream` with `bufferingNewest(1)`. Command delivery
must use an actor-owned queue when loss is unacceptable. Plugins return value
types and never import TCA or expose a Store, Effect, Publisher, View, or managed
object.

Plugins normalize transport responses into `MediaSourceFailure`. The value's
provider-neutral retry decision tells application orchestration whether time
can heal the failure and may carry a bounded delay hint. Reducers never inspect
HTTP status codes or provider response bodies. Retry remains opt-in per command:
only declared desired-state assignments may use a durable retry queue, while
ambiguous lifecycle commands are not replayed automatically.

Artwork is a just-in-time transport capability. Presentation keeps only the
secret-free fallback URL, exact media locator, and artwork kind. On a network
cache miss, the image pipeline asks the account-bound runtime for an
`ArtworkDescriptor` and applies its headers to that request only. Resolved
descriptors, headers, tokens, and runtime objects never enter TCA state.

The macOS cache identity is scoped by Source, provider item, artwork kind, and
a URL with user info, query, and fragment removed. Cached images can therefore
render without an installed runtime, while credentials never enter cache
metadata. Header-authenticated descriptors are restricted to the fallback
origin and capability-resolved requests reject redirects until a future
credential-scope contract supports authenticated CDNs safely.

## Implemented providers

Emby v1 implements manual/reverse-proxy setup, UDP discovery, authentication,
Views/Items/Latest/Resume, detail hierarchy, people, artwork descriptors,
direct-play/direct-stream resolution, playback check-ins, explicit user-state
import, and optional outbound mirror. See
[`../integrations/emby.md`](../integrations/emby.md).

UHDNow is not a separate runtime or user-visible source type. Subscribers add
the service through standard Emby setup. The canonical Emby factory owns the
retired `com.samsonlab.cinelark.uhdnow` plugin ID only as a migration alias:
legacy sources become explicit reconnect proposals, reuse their `SourceID`, and
are replaced only after standard server validation, authentication, and local
persistence succeed.

## Profile state boundary

Profile favorites and playback are local-first and independent of source
runtime state. CloudKit syncs Profile projections; source configuration, active
selection, Catalog, and mirror delivery remain local. See
[`profile-cloudkit-schema.md`](profile-cloudkit-schema.md).
