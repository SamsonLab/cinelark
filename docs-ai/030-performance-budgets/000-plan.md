# 030 — Performance Budgets: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-31 |
| **Primary refs** | [Implementation outcome](001-action.md), [Performance runbook](../../docs/performance.md) |
| **Related** | [Product specification](../../docs/product-spec.md), [Architecture](../../docs/architecture.md), [TV experience](../../shared/design/CINELARK_TV_EXPERIENCE.md) |

## Background

CineLark specifies cached-first behavior, deterministic directional interaction, and
minimal-friction playback, but its numeric launch, focus, and cache budgets remain
open. Without named intervals and a stable measurement format, performance changes
cannot be compared across builds and regressions remain subjective.

## Goals

- Define initial interaction and lifecycle budgets for app readiness, cached content,
  refreshed content, detail readiness, playback file load, and Remote command handling.
- Instrument those intervals without collecting user content, URLs, credentials, item
  identifiers, or persistent analytics.
- Use monotonic time and emit OSLog signposts plus structured local samples suitable
  for Instruments and tests.
- Separate target budgets from critical ceilings so early development can surface
  regressions without turning noisy wall-clock timing into flaky CI failures.
- Provide deterministic unit coverage for budget classification and interval lifecycle.

### Non-goals

- Adding telemetry upload, MetricKit ingestion, analytics identifiers, or a backend.
- Claiming device-independent baselines before physical release hardware is sampled.
- Enforcing wall-clock XCTest thresholds in shared CI.
- Measuring provider server latency as if it were entirely under CineLark's control.

## Initial budget model

| Interval | Target | Critical ceiling | Completion point |
| --- | ---: | ---: | --- |
| App bootstrap | 1,500 ms | 4,000 ms | Profile and Source restoration reaches ready |
| Cached library page | 150 ms | 400 ms | Safe cached page is applied to state |
| Refreshed library page | 1,500 ms | 5,000 ms | Provider refresh is applied or fails |
| Media detail | 800 ms | 2,500 ms | Primary detail response is applied or fails |
| Playback file load | 3,000 ms | 10,000 ms | Matching IINA `fileLoaded` or terminal failure |
| Remote command | 100 ms | 300 ms | Command is executed and acknowledgement is queued |
| Focus mutation | 16.67 ms | 33.34 ms | Active semantic surface accepts or rejects the directional move |

Directional focus response retains a product target of one 60 Hz display frame for
local state mutation. It is measured on the semantic UI path rather than inferred from
reducer timing; Instruments remains authoritative for the presented visual frame.
Artwork completion is reported separately and does not define semantic content
readiness.

## Design / Approach

- Introduce an app-internal performance monitor with named metrics, budget values,
  monotonic interval tokens, classification, and privacy-safe OSLog/signpost output.
- Expose the monitor through a narrow TCA dependency so reducers can start and finish
  intervals without depending on OSLog or global mutable state.
- Scope tokens to query/playback identities so late responses cannot finish a newer
  interval.
- Record successful and failed completion with the same metric; outcome is a bounded
  enum rather than an error description.
- Document a repeatable local baseline command or launch mode after the runtime
  instrumentation is in place.

## Validation

- Deterministic tests use a controlled monotonic clock or explicit elapsed values.
- Existing reducer tests prove cancellation and stale-response behavior remain intact.
- A local debug run demonstrates signpost/sample emission without sensitive values.
- Full Swift Package and macOS application tests remain green.

## Alternatives & decisions

- **XCTest `measure` as the primary gate:** rejected because shared runners and provider
  fakes do not represent couch hardware or network conditions.
- **MetricKit first:** rejected because local named intervals and interaction signposts
  are required before aggregate production diagnostics are useful.
- **One global stopwatch:** rejected because overlapping shelves, queries, and playback
  sessions require identity-scoped intervals.

## Amendments

- None.
