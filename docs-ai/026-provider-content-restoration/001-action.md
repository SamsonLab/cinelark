# 026 — Provider Content Restoration: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-28 | Confirmed that Catalog metadata retained artwork URLs and that the configured Emby service redirected image delivery on the same origin | [`000-plan.md`](000-plan.md) |
| 2026-08-28 | Scoped capability-resolved redirects to safe same-origin destinations | [`media-source-platform.md`](../../docs/interfaces/media-source-platform.md) |
| 2026-08-28 | Let authoritative Series detail recover hierarchy loading from stale initial metadata | [`emby.md`](../../docs/integrations/emby.md) |

## Outcome & current state (as of 2026-08-28)

- Artwork metadata remains secret-free and persisted as before. The network
  pipeline now follows safe same-origin redirect chains used by immutable image
  delivery while rejecting origin changes, URL credentials, and known token
  query parameters.
- `MediaDetailFeature` requests hierarchy immediately for a known Series and
  records that request. If the initial summary is stale but detail identifies a
  Series, it performs the missing seasons request exactly once and continues to
  episodes through the existing selection flow.
- The configured service audit confirmed that image delivery completes as JPEG
  after one same-origin redirect and that Series, Season, and Episode structures
  remain nonempty with the fields consumed by CineLark. No credential or private
  response body was retained.

## Validation

- The new redirect and stale-kind regression tests first failed against missing
  policy/state behavior, then passed after implementation.
- `ArtworkRequestTests` covers same-origin acceptance plus cross-origin and
  credential-query rejection.
- `MediaDetailFeatureTests` covers Movie-like stale input corrected to Series,
  followed by Season and Episode loading.
- `swift test` in `packages/apple/CineLarkKit`: 70 tests pass.
- Unsigned macOS `xcodebuild ... test`: 49 tests pass with no failures or skips.
- A credential-free live image request completes with HTTP 200, `image/jpeg`,
  and one redirect.
- `git diff --check` passes.

## Deviations from plan

- None.

## Open questions

- Authenticated cross-origin CDNs still require a future descriptor contract
  that explicitly scopes credentials to permitted origins.
