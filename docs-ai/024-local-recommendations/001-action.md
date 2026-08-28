# 024 — Local Metadata Enrichment and Recommendations: Action

| | |
| --- | --- |
| **Status** | Implemented and verified locally |
| **Date** | 2026-08-28 |
| **Scope** | Exact cached enrichment, private recommendation projection, TCA query identity, and Insights UI |

## Implemented

- Added exact-locator Catalog reads with strict Source isolation. Insights never
  issues provider requests to enrich historical Profile facts.
- Added a version-ordered media-snapshot repository write that routes to the
  Cloud or provisional store and preserves existing metadata dimensions.
- `ViewingInsightsService` now fills only missing genres and artwork, uses the
  Profile hybrid logical clock, and avoids a second write once the same cached
  evidence has been applied.
- Added a pure deterministic recommendation projector. All-time session
  duration, completion, favorites, and genres produce an explainable score;
  already viewed/favorited locators, episodes, and candidates without personal
  evidence are excluded.
- Candidate ranking uses at most 500 local Catalog summaries and emits at most
  twelve values. Provider user state is cleared before a recommendation enters
  presentation state.
- `InsightsFeature` now treats Profile, active Source, period, and request ID as
  response identity. A Source switch cancels/reloads and stale candidates cannot
  replace the current Source projection.
- Viewing Insights displays a localized recommendation shelf with up to two
  matching-genre reasons and reuses the existing poster navigation/focus model.

## Validation

- TDD red: Catalog and Profile tests initially failed because exact-locator
  reads and direct versioned snapshot writes did not exist.
- Pure recommendation tests verify ranking, reason order, viewed/favorite
  exclusion, unrelated-candidate exclusion, and provider-state clearing.
- Service integration verifies cached genre/artwork enrichment, immediate
  affinity/recommendation projection, persisted mutation ordering, and
  idempotence on a second load.
- `InsightsFeatureTests.sourceChangeReloads` verifies Source identity is part of
  the latest-wins response guard.
- `swift test --package-path packages/apple/CineLarkKit` passes 67 tests.
- Unsigned macOS tests pass 38 Swift Testing tests across 14 suites and 6 XCTest
  cases.
- `git diff --check` passes.

## Deviations from the plan

- None.

## TCA learning review

Updated `L017 — Keep rebuildable fact volume below TCA state`. The verified
lesson now records that every external input affecting a compact projection—in
this case active Source as well as Profile and period—must be included in the
effect response identity.

## Remaining product boundary

- The current algorithm is a transparent local genre baseline, not a claim of
  collaborative or editorial recommendation quality. A future service requires
  a separate privacy, consent, evaluation, and backend milestone.
