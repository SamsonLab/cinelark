# 006.004 — Completion Progress Polling

## Context

The live 0.1.12 trace reached `1501.239868 / 1501.240000` seconds, but the bridge
received only `player.closed(reason=window_closed)`. Stock IINA did not expose
the expected pause, EOF-property, or end-file callbacks before closing, and the
window-close handler's last one-second telemetry sample was not guaranteed to
contain the final position.

## Change

- Poll `core.status.position` and `core.status.duration` every 100 ms while
  keeping network position emission throttled to once per second.
- Treat a sample within 1 ms of duration as the final decoded frame. This
  sub-millisecond tolerance covers the fractional difference between mpv's last
  frame timestamp and container duration seen in the live trace without
  replacing content early.
- Emit `player.ended(reason=eof)` immediately from that poll. There is no
  additional completion timer or one-second delay.
- Keep `eof-reached`, pause-at-completion, end-file, and close-position checks as
  compatible fallback paths; terminal emission remains idempotent.

## Validation

- `npm test --prefix plugins/iina` passed 23 tests. The new regression verifies
  a 100 ms poll does not finish 2 ms early, then immediately emits EOF for the
  `1501.239868 / 1501.240000` terminal sample without running a delayed timer.
- `swift test --package-path packages/apple/CineLarkKit` passed 37 tests.
- The macOS Xcode target passed its five-episode content-replacement test with
  zero enqueue calls.
- Packaged plugin 0.1.13 as `plugins/iina/dist/CineLark.iinaplgz`; SHA-256 is
  `74c825596fbe3dfb7e25d1c62ffd5ea1cac16cb9a11649539d84645f31c65e36`.

## Current state

Implemented in the working tree on 2026-08-25 from the live 0.1.12 trace.
