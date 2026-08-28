# Viewing Insights

- **Status:** Implemented local projection, cached enrichment, and private recommendations; signed multi-device validation pending
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

When an active Source has locally cached candidates, the page also shows up to
twelve unwatched and unfavorited movie/series recommendations. Each candidate
states the one or two strongest matching genres. No generic popularity fallback
is labeled as personal recommendation when preference evidence is absent.

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
- Recommendations use all-time facts through the reference instant, independent
  of the currently selected summary period.
- Session duration and completion plus active favorites contribute bounded
  genre weights. Ranking then uses score, rating, title, and locator identity.
- Episodes, consumed/completed locators, active favorites, and candidates with
  no matching genre evidence are excluded.

## Data ownership

The Profile repository owns durable sessions and media snapshots. Optional
snapshot metadata retains genre and contributor evidence captured while a
detail is available. Provider IDs are source-local; optional TMDB/IMDb IDs are
preferred future cross-source evidence but never replace a media locator.
Explicit Emby import can add genre evidence without making provider playback
state authoritative during browsing. Snapshot updates merge metadata by
dimension: a non-empty incoming genre/director/cast dimension replaces that
dimension, while a missing or empty dimension retains existing evidence. The
current schema does not interpret absence as metadata deletion.

Insights may fill missing snapshot genres and artwork only from an exact
`MediaLocatorID` match already present in the local Catalog. It does not fetch
provider detail during projection. Enrichment receives a new Profile mutation
stamp and is idempotent once the same dimensions are present; existing
genre/director/cast dimensions are never replaced by absence.

Insights are rebuildable and therefore are not currently persisted in Core
Data or CloudKit. TCA receives only the selected period, request identity, and
compact presentation snapshot. Repository rows, managed objects, calendars,
and source runtimes do not enter Store state.
Top-title presentation retains the optional source locator from its media
snapshot so the image pipeline can resolve authenticated artwork. The resolved
descriptor and headers remain below Store state and are never part of the
Insights projection.

## Refresh and failure semantics

Changing period, active Profile, or active Source cancels the obsolete request
and starts a new one when the screen is visible. Responses must match request,
Profile, Source, and period identity before replacing the current projection.
Relevant Profile repository changes refresh the selected Insights screen.

A projection failure is recoverable and does not mutate viewing facts. Source
network failure is not a projection dependency.

## Privacy and future services

Preference dimensions and recommendation scoring remain on-device/in the
user's private Profile boundary. Candidate summaries come from the active
Source's local Catalog, and provider user state is cleared before presentation.
No history or affinity vector is uploaded. A future recommendation service must
use a separate explicit consent, privacy, evaluation, and backend contract;
raw viewing events must never be uploaded implicitly.
