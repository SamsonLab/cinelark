# 030 — Performance Budgets: Action

| | |
| --- | --- |
| **Status** | Implemented |
| **Completed** | 2026-08-31 |
| **Plan** | [000-plan.md](000-plan.md) |

## Outcome

CineLark now has seven named development budgets, privacy-safe monotonic intervals,
Points of Interest signposts, deterministic classification tests, and a repeatable
local capture/summarization workflow. No telemetry leaves the Mac, and wall-clock
latency is not used as a shared-CI pass/fail gate.

## Implemented

- Added target and critical ceilings for bootstrap, cached and refreshed library
  pages, media detail, IINA file load, Remote commands, and semantic focus mutation.
- Added one performance dependency and monitor backed by `ContinuousClock`, OSLog, and
  `OSSignposter`; emitted samples contain only metric, elapsed time, rating, and outcome.
- Instrumented App, Library, Detail, Playback, and Remote completion points, including
  failures and cancellations. Query- and playback-scoped tokens prevent stale work
  from finishing a newer interval.
- Instrumented focus on `ShortcutCoordinator`'s semantic UI path. The signpost measures
  local mutation; Instruments remains authoritative for presented-frame timing.
- Kept performance interval tokens out of semantic TCA state equality so observability
  cannot alter feature behavior or TestStore assertions.
- Added scripts to capture filtered NDJSON and summarize successful-sample median, P95,
  maximum, target overruns, critical overruns, and failed/cancelled outcomes.
- Added the contributor-facing performance runbook and synchronized the product
  specification with the initial numeric budgets.

## Verification

- Performance budget unit tests cover ordered budgets, exact threshold boundaries,
  and subsecond duration conversion.
- Remote capability policy tests cover advertised/routed capability consistency.
- `swift test --package-path packages/apple/CineLarkKit`: 73 passed, 0 failed.
- macOS `xcodebuild test` with signing disabled: 60 passed, 0 failed.
- Capture shell syntax, `log stream` options, summarizer entry point, Xcode project
  regeneration, and final whitespace validation: passed.

## Deviations and limits

- Numeric budgets are initial engineering hypotheses, not physical-device baselines.
  A meaningful sample requires stable provider, cache, IINA, Remote, power, and display
  conditions; the runbook records that controlled workflow instead of fabricating a
  baseline from unit-test fakes.
- Provider refresh and playback intervals include external latency by design. Their
  outcome and metric remain separate so comparisons can distinguish successful work
  from fast failures and cancellations.
- Artwork completion is excluded from content readiness. Focus signposts do not prove
  the frame was presented; visual-frame confirmation requires Instruments.
