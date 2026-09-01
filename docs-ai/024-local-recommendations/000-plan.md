# 024 — Local Metadata Enrichment and Recommendations: Plan

| | |
| --- | --- |
| **Status** | Implemented and verified locally |
| **Anchor date** | 2026-08-28 |
| **Primary refs** | [Action](001-action.md), [Balanced weighting](002-balanced-recommendation-weighting.md), [Viewing insights](../../docs/product/viewing-insights.md) |
| **Related** | [Viewing insights](../../docs/product/viewing-insights.md), [Personal viewing memory](../../docs/decisions/0011-personal-viewing-memory.md), [Media source platform](../../docs/interfaces/media-source-platform.md) |

## Background

CineLark already projects month, quarter, year, and all-time viewing summaries
from Profile-owned facts. Older snapshots can still lack genre evidence even
when the local Catalog has since learned it, and the app does not yet turn the
resulting preference model into actionable discovery.

The product value is long-lived Apple-ID viewing memory, not another provider
Profile. Enrichment and recommendation therefore remain local-first: Catalog
metadata may improve the private Profile snapshot, while candidate ranking is
computed entirely on-device and never uploads raw history or affinity vectors.

## Goals

- Enrich missing historical snapshot genres and artwork from exact local
  Catalog locators without issuing a provider request.
- Preserve existing snapshot dimensions and use the Profile mutation clock for
  every persisted enrichment.
- Rank unseen movie/series candidates from the active Source using local
  session, completion, favorite, and genre evidence.
- Return at most twelve compact, deterministic recommendations with one or two
  human-readable matching-genre reasons.
- Exclude already viewed or favorited locators and clear provider user state
  from candidate presentation.
- Surface recommendations in Viewing Insights using the existing navigation
  and poster interaction model.
- Keep the projector/service outside TCA; inject one value client and retain
  request/Profile/Source/period identity in `InsightsFeature`.

### Non-goals

- A CineLark recommendation backend, collaborative filtering, or uploading
  viewing history/affinity vectors.
- Fetching TMDB, Trakt, or provider detail metadata during Insights loading.
- Cross-source content merging or recommendations when no Source is active.
- Persisting recommendation results in Core Data or CloudKit.
- Claiming semantic quality beyond an explainable local genre baseline.

## Design / Approach

`CatalogRepository` gains an exact-locator read used only for locally cached
metadata. `ProfileRepository` gains a versioned media-snapshot write routed to
the correct Cloud or provisional store. The write emits a metadata-specific
change so Feature coordination does not confuse enrichment with playback or
favorite state.

`ViewingInsightsService` loads Profile facts, exact Catalog matches, and a
bounded active-Source candidate page. Missing genres/artwork are filled without
replacing non-empty Profile metadata dimensions. Each changed snapshot receives
a new hybrid logical mutation stamp before persistence.

`ViewingRecommendationProjector` is a pure deterministic function:

- watched sessions contribute duration plus completion weight to each genre;
- active favorites contribute a bounded genre preference weight;
- candidates must be movies or series, have at least one matching genre, and
  have no consumed/completed session or active favorite for the same locator;
- rank by total matching affinity, provider-neutral rating tie-break, title,
  then stable locator identity;
- reasons are the two strongest matched genres.

The selected Insights period affects summaries only. Recommendations use
all-time facts through the reference instant, so a month/quarter toggle does
not redefine the user's durable preference model.

## Alternatives & decisions

- **Call Emby detail for every historical item:** rejected because Insights
  would become network-bound, expensive, and cancellation-heavy.
- **Store affinity or recommendation rows in CloudKit:** rejected because both
  are rebuildable projections and would increase privacy/conflict surface.
- **Use ratings/popularity without personal evidence as fallback:** rejected;
  CineLark must label personal recommendations truthfully.
- **Put the Catalog actor in TCA State:** rejected. TCA owns query identity and
  presentation only; actor/repository lifetimes remain dependency-owned.

## Validation

- TDD projector tests cover deterministic ranking, favorite/completion weight,
  viewed-item exclusion, reason selection, and provider-state clearing.
- Repository tests cover exact source/locator reads and versioned snapshot
  enrichment without overwriting existing metadata dimensions.
- Service integration proves cached-only enrichment is persisted and immediately
  reflected in affinities/recommendations.
- `TestStore` proves Profile/Source identity guards prevent stale recommendation
  responses from replacing current state.
- Full SwiftPM and unsigned macOS test suites pass, followed by source scans and
  `git diff --check`.

## Amendments

- Updated 2026-08-28: Rebalanced durable preference signals and removed
  multi-genre cardinality bias — see
  [002-balanced-recommendation-weighting.md](002-balanced-recommendation-weighting.md).
