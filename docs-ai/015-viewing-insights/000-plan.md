# 015 — Viewing Insights: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-27 |
| **Primary refs** | [`001-action.md`](001-action.md), [`../../docs/product/viewing-insights.md`](../../docs/product/viewing-insights.md) |
| **Related** | [`../014-viewing-identity-and-sync/000-plan.md`](../014-viewing-identity-and-sync/000-plan.md), [`../../docs/decisions/0011-personal-viewing-memory.md`](../../docs/decisions/0011-personal-viewing-memory.md), [`../../docs/interfaces/profile-cloudkit-schema.md`](../../docs/interfaces/profile-cloudkit-schema.md) |

## Background

CineLark now persists source-independent viewing sessions and immutable
playback events. Those facts establish the product's long-term value only when
they can be turned into useful personal memory: monthly, quarterly, annual, and
all-time summaries plus title, genre, director, and actor affinities.

The first projection must remain local-first and rebuildable. It should not add
a recommendation backend, upload derived interests, or persist a second source
of truth before projection stability is proven.

## Goals

- Add a pure Swift `CineLarkInsights` module that derives value snapshots from
  `ViewingSession` and `ProfileMediaSnapshot` values without importing TCA,
  Core Data, SwiftUI, or provider plugins.
- Support month, quarter, year, and all-time ranges with explicit calendar and
  time-zone boundaries.
- Project total watched time, sessions, completions, distinct titles, active
  days, longest streak, daily activity, and ranked titles.
- Capture optional genre/director/cast metadata in the durable media snapshot
  used by playback and favorite writes, while retaining backward-compatible
  decoding for existing snapshots.
- Expose ranked genre, director, and actor dimensions when metadata exists;
  absence must degrade to an empty dimension rather than block the summary.
- Add a TCA `InsightsFeature` and a content-level sidebar destination. Profile
  changes and relevant repository invalidations refresh the selected range.
- Keep Store state limited to query state and the compact presentation
  snapshot; sessions, events, repositories, and calendars remain dependencies.

### Non-goals

- Personalized recommendations, collaborative filtering, trending feeds, or a
  CineLark service backend.
- Persisting or CloudKit-syncing derived `InsightSnapshot` records.
- Reconstructing metadata for historical records that were saved before the
  enrichment fields existed.
- Exact wall-clock engagement accounting or partial allocation of a session
  across period boundaries.
- Cross-Profile or cross-Apple-ID comparison.

## Design / Approach

1. Extend `ProfileMediaSnapshot` with an optional, value-typed metadata block.
   Optional storage preserves decoding of existing payloads. Contributor
   snapshots retain provider identity plus optional external IDs for later
   cross-source reconciliation.
2. Pass the loaded detail metadata through the existing play delegate chain so
   the playback transaction records the same metadata used to render the
   selected title. Favorite writes use the same projection helper.
3. `ViewingInsightsProjector` accepts explicit sessions, snapshots, reference
   date, and `Calendar`. Range generation is deterministic and separately
   tested for month, quarter, year, and all-time behavior.
4. A session is attributed to the period containing `endedAt ?? modifiedAt`.
   Its full watched duration is attributed to every associated genre/person;
   dimension totals therefore describe affinity and are not additive to the
   global total.
5. `ViewingInsightsService` queries the Profile repository, loads only snapshot
   keys referenced by sessions, and invokes the pure projector. It owns no
   cache or mutable state.
6. `InsightsClient` wraps the service for TCA. `InsightsFeature` uses a
   feature-scoped cancellation ID and request identity so Profile/range changes
   are latest-wins even if a repository query completes late.
7. The macOS view presents compact summary cards, an activity chart, ranked
   titles, and available affinity dimensions. It remains useful with no active
   Source because facts belong to the Profile.

## Alternatives & decisions

- Computing analytics directly in the SwiftUI view was rejected because range
  semantics, grouping, and metadata attribution require deterministic tests.
- Storing all sessions in TCA state was rejected because durable fact volume is
  repository-owned and unnecessary for rendering.
- Persisting derived summaries was deferred. Projection cost and schema
  stability must be measured before adding invalidation and migration burden.
- Querying Emby for historical metadata at render time was rejected because
  insights must work offline and must not couple personal memory to a Source's
  continued availability.
- Name-only contributor aggregation is used as a fallback when external IDs are
  unavailable. External identifiers remain the preferred future merge key.

## Validation

- Pure projector tests cover period boundaries, empty history, pause/seek-safe
  watched totals, ranking, streaks, metadata gaps, and deterministic ties.
- Profile snapshot tests prove legacy payloads decode without the optional
  metadata block.
- TCA `TestStore` tests cover initial load, range changes, stale responses,
  Profile changes, and repository invalidation refresh.
- The complete SwiftPM and unsigned macOS test suites must pass.

## Amendments
