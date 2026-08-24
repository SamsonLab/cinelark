# 006.003 — Keep the Managed Player Open at EOF

## Context

A live plugin 0.1.11 reproduction produced normal `player.fileLoaded`, state,
position, and sync traffic, but no `player.ended`. IINA closed the player window
at the end and the bridge reported `player.closed(reason=window_closed)`.
Property-based EOF observation cannot trigger after IINA tears down the managed
player first.

## Change

- Set mpv `keep-open=yes` before each managed `core.open`. The managed window
  remains alive at EOF so `eof-reached` can trigger replacement in that window.
- Treat a transition to paused with sampled progress at or above 99.9% as EOF.
  This covers IINA's keep-open terminal state when no distinct end event is
  exposed; ordinary mid-playback pause remains non-terminal.
- On `iina.window-will-close`, log the last sampled position and duration. If no
  terminal event has been sent and the sampled position is within the existing
  terminal tolerance, emit `player.ended(reason=eof)` before `player.closed` as
  a fallback.
- Raise the minimum plugin version to prevent the close-at-EOF implementation
  from being treated as current.

## Validation

- The live 0.1.11 trace established the failure boundary: regular telemetry and
  metadata discovery succeeded, but the only terminal lifecycle message was
  `player.closed(reason=window_closed)`.
- `npm test --prefix plugins/iina` passed 22 tests, including `keep-open` before
  `core.open`, pause-at-100%-as-EOF, non-terminal ordinary pause,
  argument-free EOF, replacement reuse, and terminal-position window-close
  fallback.
- `swift test --package-path packages/apple/CineLarkKit` passed 37 tests.
- The macOS Xcode target passed its five-episode replacement test with zero
  enqueue calls.

## Current state

Implemented on 2026-08-25 and first included in plugin 0.1.12. Live diagnostics
then required [004-completion-progress-polling.md](004-completion-progress-polling.md)
and [005-replacement-lifecycle-isolation.md](005-replacement-lifecycle-isolation.md),
making 0.1.15 the current minimum compatible version.
