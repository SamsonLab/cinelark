# Viewing Insights

- **Status:** Implemented local projection; signed multi-device validation pending
- **Source of truth:** Profile viewing facts and media snapshots

Viewing Insights turns CineLark's source-independent viewing memory into useful
personal summaries. It remains available when a media Source is disconnected
because neither Emby state nor provider availability owns the projection.

## Current surface

The macOS content sidebar exposes four ranges:

- current month;
- current calendar quarter;
- current calendar year;
- all time through the current instant.

Each range can show total watched time, session and completion counts, distinct
titles, active days, longest streak, daily activity, top titles, and available
genre/director/actor affinities. Missing historical metadata removes only the
affected affinity section; it does not hide the rest of the summary.

## Projection contract

`CineLarkInsights` accepts explicit `ViewingSession` and
`ProfileMediaSnapshot` values plus a reference date and `Calendar`. It returns a
compact immutable `ViewingInsightsSnapshot`.

- Session activity is dated by `endedAt ?? modifiedAt`.
- Only sessions with consumed time or an explicit completion are included.
- Future activity relative to the reference instant is excluded.
- A session is credited wholly to one period; it is not split at midnight or a
  period boundary.
- A session's watched duration is credited to every associated affinity
  dimension. Dimension totals are ranking weights, not additive subtotals.
- Title ranking uses watched time, session count, then title for deterministic
  ties. Dimension ranking uses watched time, session count, then name.
- Results are capped to ten titles and ten values per affinity dimension.

## Data ownership

The Profile repository owns durable sessions and media snapshots. Optional
snapshot metadata retains genre and contributor evidence captured while a
detail is available. Provider IDs are source-local; optional TMDB/IMDb IDs are
preferred future cross-source evidence but never replace a media locator.

Insights are rebuildable and therefore are not currently persisted in Core
Data or CloudKit. TCA receives only the selected period, request identity, and
compact presentation snapshot. Repository rows, managed objects, calendars,
and source runtimes do not enter Store state.

## Refresh and failure semantics

Changing period or active Profile cancels the obsolete request and starts a new
one when the screen is visible. Responses must match request, Profile, and
period identity before replacing the current projection. Relevant Profile
repository changes refresh the selected Insights screen.

A projection failure is recoverable and does not mutate viewing facts. Source
network failure is not a projection dependency.

## Privacy and future services

Preference dimensions remain on-device/in the user's private Profile boundary.
A future recommendation service may consume an explicit privacy-preserving
projection, but raw viewing events must not be uploaded implicitly. Persisted
aggregates, historical enrichment, recommendations, and cross-Profile analysis
remain separate milestones.
