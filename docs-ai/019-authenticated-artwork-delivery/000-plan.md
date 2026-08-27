# 019 — Authenticated Artwork Delivery: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-27 |
| **Primary refs** | [`001-action.md`](001-action.md), [`../../docs/interfaces/media-source-platform.md`](../../docs/interfaces/media-source-platform.md) |
| **Related** | [Media source platform](../011-media-source-platform/000-plan.md), [Emby metadata fidelity](../018-emby-metadata-fidelity/000-plan.md), [`docs/integrations/emby.md`](../../docs/integrations/emby.md) |

## Background

Media plugins already return `ArtworkDescriptor` values containing a secret-free
URL plus request headers. The macOS image surface currently gives Kingfisher only
the URL, so an Emby server that protects image endpoints cannot render uncached
posters or backdrops.

Moving account tokens into artwork URLs, Catalog metadata, cache keys, SwiftUI
state, or TCA state would fix rendering by violating the security and ownership
boundaries established for media plugins.

## Goals

- Route the plugin artwork capability through the macOS image pipeline.
- Resolve authorization only when Kingfisher needs a network request; cache hits
  must remain local and work without a live runtime.
- Keep authorization headers transient below Feature/Application state.
- Use a stable, credential-free cache identity scoped by Source, provider item,
  artwork kind, and sanitized fallback URL.
- Reject credential-bearing or cross-origin descriptor URLs before attaching
  headers, and reject redirects for capability-resolved artwork in v1.
- Cover library/detail posters and persisted top-title artwork in Insights.
- Add deterministic tests for request mutation, unsafe descriptor rejection,
  cache-key redaction, platform capability routing, and locator projection.

### Non-goals

- Adding image-prefetch scheduling or a separate artwork Feature.
- Persisting plugin runtime, token, headers, or descriptors in TCA State.
- Supporting authenticated cross-origin CDNs or redirect credential scoping.
- Changing the existing 512 MiB artwork cache policy or Settings clear action.
- Backfilling artwork URLs for Profile snapshots that never captured one.

## Design / Approach

### Capability routing

`MediaSourcePlatform` adds a small `artwork(for:kind:)` method that locates the
account-bound runtime and invokes its optional artwork client. The composition
root injects a value-typed `ArtworkResolutionClient` into the SwiftUI environment.
This client contains only an async closure; it does not expose a runtime or
observable state.

Views continue to pass stable provider-neutral locators and display URLs.
`ArtworkView` does not start a task or retain a descriptor. Its Kingfisher async
request modifier resolves the descriptor immediately before a cache-miss
download and adds headers to that one request.

### Request and cache security

The request modifier applies these rules:

1. no reference means the existing URL-only path remains unchanged;
2. an absent capability result falls back to the original public URL;
3. a capability error cancels the network request while preserving cached data;
4. descriptor URLs must use HTTP(S), contain no URL credentials, and contain no
   known token query item;
5. a descriptor carrying headers must remain on the fallback URL's origin;
6. descriptor headers are attached only to the ephemeral request;
7. redirects are rejected for capability-resolved artwork.

The Kingfisher cache key contains Source ID, provider item ID, artwork kind, and
a sanitized URL with user info, query, and fragment removed. Tokens and headers
therefore never enter cache filenames or metadata.

### Presentation identity

Library cards derive a locator from the active single Source and the summary's
provider item ID. Detail uses its explicit route locator. `ViewingInsightTitle`
retains the optional locator already present in the Profile media snapshot so
offline projections can address the correct plugin when that Source is installed.

This locator remains a compact semantic value in presentation state; resolved
headers and descriptors do not.

## Alternatives & decisions

- **Append the Emby token to image URLs:** rejected because URLs escape through
  logs, Catalog, Profile snapshots, cache keys, and UI diagnostics.
- **Resolve descriptors in every Feature reducer:** rejected because headers
  would enter Store state and eager list resolution would duplicate work before
  Kingfisher knows whether the image is cached.
- **Let `ArtworkView` call a dependency in `.task`:** rejected because it would
  put business-capability orchestration in the View and duplicate cancellation.
- **Allow redirects and trust URLSession header behavior:** rejected because a
  custom authorization header has no safe generic redirect scope.
- **Key cache entries by URL only:** rejected because identical server paths can
  represent different account-bound Sources and reconfiguration needs a stable
  source-aware boundary.

## Amendments

- None.
