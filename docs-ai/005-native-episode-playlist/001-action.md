# 005 — Native Episode Playlist: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-24 | Recorded rolling native-playlist design and rejected full-series URL pre-resolution | Working tree |
| 2026-08-24 | Added `player.enqueue` across Swift, Rust, and the IINA plugin | Working tree |
| 2026-08-24 | Replaced provider-driven EOF continuation with a two-entry rolling IINA queue | Working tree |
| 2026-08-24 | Bumped the required IINA plugin version to 0.1.8 and updated current-state docs | Working tree |
| 2026-08-24 | Corrected JSExport playlist insertion, added a telemetry recovery probe, and validated a real five-second EOF transition with plugin 0.1.9 | Working tree |
| 2026-08-24 | Consolidated reusable IINA plugin engineering lessons and the real-EOF smoke-test runbook | [004](004-iina-plugin-engineering-lessons.md) |
| 2026-08-25 | Made telemetry silence non-terminal and restored rolling refill plus immediate per-item provider synchronization | [005](005-telemetry-liveness-and-item-sync.md) |
| 2026-08-25 | Superseded playlist continuation with single-content sequential replacement | [006](../006-sequential-episode-replacement/000-plan.md) |

## Outcome before supersession (as of 2026-08-25)

This section describes the final native-playlist implementation. It was
superseded later that day by
[006 — Sequential episode replacement](../006-sequential-episode-replacement/000-plan.md).

Series playback now starts the selected episode immediately and discovers the
remaining cross-season episode order in the background. The coordinator resolves
only enough assets and capability URLs to keep two future episodes ready.

The playback bridge treats the first descriptor ID as the managed-player session
ID. `player.enqueue` adds later descriptors with independent playback IDs. The
IINA plugin stores the descriptor-to-URL mapping in memory, appends URLs through
`playlist.add`, and switches item identity on `file-loaded`.

Natural EOF finalizes the old item locally and schedules its stopped report on
the existing serialized reporter path. It does not await provider state before
mpv advances. Loading a queued item consumes its prepared state and triggers the
next rolling refill. Movies and episode playback without a series ID continue to
use a single-item session.

Telemetry silence now triggers a state probe but never finalizes playback or
clears the logical queue. Each activated item uploads its initial progress
immediately, and a previous item remains addressable by playback ID until its
own terminal event is reported. The two-future-URL window therefore refills
across all remaining discovered episodes instead of becoming a fixed two-item
tail after a transient telemetry gap.

The contributor-facing contract is updated in:

- [`docs/interfaces/playback-bridge.md`](../../docs/interfaces/playback-bridge.md)
- [`docs/architecture.md`](../../docs/architecture.md)
- [`docs/integrations/iina-plugin-api.md`](../../docs/integrations/iina-plugin-api.md)

## Validation

- `npm test --prefix plugins/iina` passed 18 tests, including native enqueue,
  item transition, main-run-loop routing, EOF, and URL-redaction coverage.
- `npm run package --prefix plugins/iina` produced
  `plugins/iina/dist/CineLark.iinaplgz` for plugin version 0.1.9.
- `cargo +1.95.0 test --locked --manifest-path packages/rust/cinelark-bridge/Cargo.toml`
  passed 11 tests, including broker acceptance of `player.enqueue`.
- `swift test --package-path packages/apple/CineLarkKit` passed 37 tests,
  including queued event-to-playback-ID routing and plugin update detection.
- `xcodebuild -project apps/macos/CineLark.xcodeproj -scheme CineLark
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
  build` completed with `BUILD SUCCEEDED`.
- `git diff --check` and Rust formatting validation completed without errors.
- The macOS `CineLarkTests` target passed its five-episode rolling-queue
  regression, including an unanswered telemetry probe, two refills, reversed
  `fileLoaded`/EOF ordering, immediate progress uploads, and stopped reports.

## Deviations from plan

- No aggregate `PlaybackQueueDescriptor` was added. Reusing the first playback
  ID as the session ID and adding a narrow launcher `enqueue` operation kept the
  protocol change smaller while preserving per-item IDs.
- Queue discovery waits for all season metadata before the first rolling refill.
  Initial playback is unaffected because discovery runs after `player.play`.
- The final live smoke used the user's authenticated playback account, real
  capability URLs, and a five-second-to-EOF seek. See
  [003-explicit-playlist-append.md](003-explicit-playlist-append.md) for the
  observed queue and transition results.

## Open questions

- Validate a season-boundary transition on stock IINA 1.4.4.
- Decide whether automatic entries should inherit a codec/resolution preference
  instead of retaining the existing first-asset policy.
- Define retry/backoff behavior when discovery or a rolling URL refill fails.
