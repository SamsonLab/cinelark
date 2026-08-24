# 006.002 — Stock IINA EOF Detection

## Context

The first live stock-IINA smoke test did not replace the completed episode.
The per-player plugin registered `mpv.end-file` and expected its callback to
receive an object containing `reason`. IINA's public plugin API declares generic
`mpv.*` callbacks without event arguments and directs plugins to query mpv
properties for associated state. Unit tests supplied a synthetic detail object,
so they did not reproduce the stock runtime behavior. The emitted end reason
therefore became `unknown`, and the macOS coordinator correctly declined to
continue because it only replaces content after natural EOF.

## Change

- Observe `mpv.eof-reached.changed` and query `mpv.getFlag("eof-reached")` to
  identify natural completion before mpv clears the property.
- Treat `mpv.end-file` as an argument-free notification. Use the last sampled
  position and duration only as a fallback when the EOF property transition was
  not observed.
- Add privacy-safe diagnostic logging at the player plugin, global plugin,
  bridge-process client, launcher, and coordinator decision boundaries. Never
  log media URLs, pairing material, request authentication, or provider data.
- Raise the required plugin version so the corrected event listener is
  installed before playback starts.

## Validation

- `npm test --prefix plugins/iina` passed 20 tests. The regressions invoke
  `mpv.end-file` without an argument, verify `eof-reached` emits one natural EOF,
  verify terminal-position fallback, and keep the player available for a
  replacement command.
- `swift test --package-path packages/apple/CineLarkKit` passed 37 tests.
- The CineLark Xcode test target passed its five-episode replacement regression
  with zero enqueue calls. Its emitted OSLog trace showed EOF classification,
  metadata resolution, replacement dispatch, file load, and per-item sync for
  every transition.

## Current state

Implemented on 2026-08-25. This correction shipped in plugin 0.1.11; live
diagnostics subsequently required the `keep-open` and direct progress-polling
changes in [003-keep-managed-player-open.md](003-keep-managed-player-open.md)
and [004-completion-progress-polling.md](004-completion-progress-polling.md).
Replacement lifecycle isolation in
[005-replacement-lifecycle-isolation.md](005-replacement-lifecycle-isolation.md)
makes 0.1.15 the current minimum compatible version. Use
`scripts/observe_playback_logs.sh` for a combined IINA and CineLark trace.
