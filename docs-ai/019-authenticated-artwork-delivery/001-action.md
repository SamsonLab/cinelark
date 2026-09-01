# 019 — Authenticated Artwork Delivery: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-27 | Routed the optional artwork capability through `MediaSourcePlatform` | [`media-source-platform.md`](../../docs/interfaces/media-source-platform.md) |
| 2026-08-27 | Added a just-in-time Kingfisher request modifier and credential-free cache identity | [`000-plan.md`](000-plan.md) |
| 2026-08-27 | Added exact artwork locators to Library, Detail, and Insights presentation | [`viewing-insights.md`](../../docs/product/viewing-insights.md) |
| 2026-08-27 | Archived the validated protected-resource state boundary as TCA learning L020 | [`TCA-learn.md`](../010-tca-application-architecture/TCA-learn.md#l020--credential-bearing-presentation-resources-stay-below-store-state) |
| 2026-08-28 | Allowed validated same-origin redirects while preserving the cross-origin credential boundary | [Provider content restoration](../026-provider-content-restoration/001-action.md) |

## Outcome & current state (as of 2026-08-28)

- `MediaSourcePlatform` resolves artwork against the installed account-bound
  runtime and preserves the capability's optional nature.
- The composition root injects a closure-only artwork client into SwiftUI. It
  exposes neither plugin runtime nor observable state.
- Kingfisher resolves an `ArtworkDescriptor` immediately before a cache-miss
  download. Existing cached images remain available without a runtime or token.
- Library cards derive exact locators from the active Source, Detail uses its
  route locator, and Insights retains the locator from the Profile snapshot.
- Descriptor headers exist only on the ephemeral `URLRequest`. Protected URLs,
  headers, and descriptors never enter TCA state, Catalog, Profile, or cache
  identity.
- The request policy rejects non-HTTP(S), URL credentials, known token query
  names, cross-origin header forwarding, and cross-origin redirects. Safe
  same-origin redirects are followed for immutable image delivery. Public
  header-free descriptors may still select another origin without forwarding
  credentials.
- Existing Settings cache size and one-click clear behavior continues to cover
  the authenticated artwork cache.

## Validation

- The platform capability test initially failed to compile because the actor had
  no artwork route, confirming the new contract began red.
- `ArtworkRequestTests` covers ephemeral header application, cross-origin and
  query-credential rejection, unsafe fallback rejection, and cache-key
  redaction.
- The Insights projector test verifies the exact snapshot locator survives into
  its compact top-title projection.
- `swift test` in `packages/apple/CineLarkKit`: 67 tests pass.
- Unsigned `xcodebuild ... CODE_SIGNING_ALLOWED=NO test`: 38 macOS application
  and TCA tests pass without compiler warnings.
- `git diff --check` passes.

## Deviations from plan

- None.

## Open questions

- A provider that requires authenticated cross-origin artwork or redirects
  needs a descriptor contract that scopes each credential to allowed origins.
- Image-tag-aware cache invalidation and proactive prefetch remain separate
  performance work; the current expiration and user-controlled purge remain the
  freshness boundary.
