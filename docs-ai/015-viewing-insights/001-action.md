# 015.001 — Viewing Insights Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-27 | Added local-first period and affinity projections | [`../../docs/product/viewing-insights.md`](../../docs/product/viewing-insights.md) |
| 2026-08-27 | Added a cancellable TCA query surface and content destination | [`../010-tca-application-architecture/TCA-learn.md`](../010-tca-application-architecture/TCA-learn.md#l017--keep-rebuildable-fact-volume-below-tca-state) |

## Outcome & current state (as of 2026-08-27)

- `CineLarkInsights` is a pure Swift module. Its projector derives month,
  quarter, year, and all-time snapshots from Profile-owned viewing sessions and
  media snapshots without importing TCA, SwiftUI, Core Data, or source plugins.
- Projections include watched time, session and completion counts, distinct
  titles, active days, longest streak, daily activity, ranked titles, and
  available genre/director/actor affinities.
- `ProfileMediaSnapshot` now carries an optional value-typed metadata block.
  Detail favorites and playback writes retain genre and contributor evidence;
  legacy encoded snapshots remain decodable.
- `InsightsFeature` stores only query identity, loading/failure state, and the
  compact projection. It cancels obsolete loads and rejects responses whose
  request, Profile, or period identity is stale.
- The macOS content sidebar now exposes Insights independently of the active
  Source. The view provides period selection, summary cards, daily activity,
  ranked titles, affinity cards, and explicit loading/empty/failure states.
- Active Profile changes update the feature context. Profile repository
  invalidations refresh Insights only while that destination is selected.

## Validation

- `swift test --package-path packages/apple/CineLarkKit`: 68 tests across 7
  suites pass. Insights coverage verifies empty history, calendar/time-zone
  ranges, period boundaries, deterministic rankings, streaks, missing metadata,
  and legacy snapshot decoding.
- Unsigned `xcodebuild ... test`: all 30 macOS tests pass. TCA coverage verifies
  initial load, period and Profile changes, stale-response rejection,
  repository invalidation refresh, and metadata preservation in playback
  writes.
- `git diff --check` passes for the milestone changes.

## Deviations from plan

- A session is attributed wholly to the period containing
  `endedAt ?? modifiedAt`; sessions are not split across date boundaries.
- Dimension watch totals are affinity weights. A session contributes its full
  watched duration to each associated genre/person, so dimensions are not
  additive to total watch time.
- Contributor external IDs are optional in the durable snapshot. Current media
  detail credits expose source-local provider IDs; TMDB/IMDb IDs can be retained
  when a future source mapping supplies them.
- Derived snapshots are rebuilt on demand and are not persisted or synced.

## Follow-up

- Run signed two-device CloudKit scenarios before treating cross-device viewing
  facts or Insights as release-ready.
- Add a historical metadata enrichment policy only after cross-source matching
  evidence and privacy boundaries are defined.
- Measure local projection cost before introducing persisted aggregates.
- Treat recommendation work as a separate service boundary that consumes
  privacy-preserving preferences; it must not change Profile fact ownership.
