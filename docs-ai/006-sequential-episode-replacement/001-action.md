# 006 — Sequential Episode Replacement: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-25 | Superseded native playlist continuation with EOF-driven content replacement | Working tree |
| 2026-08-25 | Kept metadata-only episode discovery and removed coordinator calls to `player.enqueue` | Working tree |
| 2026-08-25 | Added an EOF replacement grace period and raised the IINA plugin requirement to 0.1.10 | Working tree |
| 2026-08-25 | Added five-episode app coverage and same-managed-window plugin coverage | Working tree |
| 2026-08-25 | Corrected stock-IINA EOF detection, added bridge diagnostics, and raised the plugin requirement to 0.1.11 | Working tree |
| 2026-08-25 | Used `keep-open=yes` and pause-at-completion detection after live logs showed IINA closing or pausing before EOF telemetry; raised the plugin requirement to 0.1.12 | Working tree |
| 2026-08-25 | Added direct 100 ms completion polling after a live trace reached the final frame without emitting EOF; raised the plugin requirement to 0.1.13 | Working tree |
| 2026-08-25 | Matched manual stop-then-play replacement, isolated outgoing lifecycle callbacks, and prohibited replacement-timeout window creation; raised the plugin requirement to 0.1.14 | Working tree |
| 2026-08-25 | Reduced completion polling from 100 ms to 500 ms without changing the 1 ms terminal-frame tolerance; raised the plugin requirement to 0.1.15 | Working tree |
| 2026-08-25 | Bound progress writes to playback snapshots, added a coalescing serial worker and stopped barriers, and serialized success-driven App refresh | [006-playback-progress-synchronization.md](006-playback-progress-synchronization.md) |

## Outcome & current state (as of 2026-08-25)

The managed IINA player contains one CineLark episode. The coordinator discovers
the ordered remainder of the series as metadata only. Natural EOF finalizes the
current episode, resolves the next episode's first asset and capability URL, and
sends a new `player.play` descriptor through the launcher's `open` operation.

The global plugin reuses its existing managed player instance. The per-player
plugin handles the new play command with `core.open`, which replaces the current
content and native playlist instead of appending another entry. The coordinator
does not call `player.enqueue` for automatic continuation.

Plugin 0.1.15 keeps the managed player open at EOF and polls position and
duration every 500 ms. When the sample reaches the final frame within a 1 ms
timestamp tolerance, it emits EOF immediately; there is no additional timer or
fixed delay. Property, pause, end-file, and window-close EOF paths remain
idempotent fallbacks because stock IINA does not consistently expose all mpv
callbacks.

At the final frame, the player pauses to hold the existing window. The
coordinator then sends `player.stop` for the outgoing session followed by
`player.play`, exactly like a second manual in-app play action. The per-player
plugin keeps the outgoing session authoritative until the new file loads, so
late EOF callbacks cannot end the incoming episode. The global plugin never
creates another player as a replacement acknowledgement-timeout fallback.

The plugin keeps an EOF-idle player available for up to 30 seconds while the
next asset and capability URL resolve. The timeout is bound to the ended
playback ID, so a delayed callback cannot close replacement content. Progress
uploads when each new item loads, and stopped reports remain serialized by
episode. Privacy-safe logs cover the player, global plugin, broker process,
launcher, and coordinator routing decisions.

Progress synchronization now converts mutable playback state into immutable,
playback-ID-scoped snapshots. A single worker serializes writes, coalesces a
slow provider's pending progress to the latest same-item snapshot, and reserves
each stopped write before the replacement item can enqueue initial progress.
Natural EOF reports the known duration as its terminal position. Only a
successful stopped request advances the observable playback revision and queues
the corresponding App refresh; Continue Watching refreshes are serialized but
do not block a later manual play action.

## Validation

- The macOS coordinator regression opened episodes 1–5 through five
  `PlaybackDescriptor` values and observed zero enqueue calls.
- The same regression left a telemetry probe unanswered and verified immediate
  progress uploads for all five episodes plus stopped reports at the completed
  positions for episodes 1–4.
- IINA tests verified direct completion detection against the terminal position
  from the live trace, outgoing EOF isolation until replacement file-load, a
  replacement command surviving EOF idle finalization, and replacement timeout
  without a second managed player instance.
- The macOS regression verified every automatic transition sends `player.stop`
  for the outgoing playback ID before opening the next descriptor, matching
  manual in-app replacement across episodes 1–5.
- `xcodebuild ... test` passed the macOS target.
- `swift test --package-path packages/apple/CineLarkKit` passed 37 tests.
- `npm test --prefix plugins/iina` passed 23 tests.
- The macOS synchronization regressions verified exact initial-upload count,
  old stopped before replacement progress, stale timer isolation, terminal
  duration clamping, slow-provider coalescing, failed-stopped UI semantics, and
  end-to-end Continue Watching refresh.

## Deviations from plan

- Reusing the player required a plugin-side EOF grace period because the former
  750 ms idle fallback could close the managed window before provider URL
  resolution completed.
- `player.enqueue` remains implemented for version-1 protocol compatibility but
  is no longer used by the application coordinator.

## Open questions

- Run a live stock-IINA smoke test after installing plugin 0.1.15 and fully
  restarting IINA.
- Decide whether the 30-second replacement grace should become an explicit
  coordinator-to-plugin continuation intent in a future protocol version.
