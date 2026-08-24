# 005.005 — Telemetry Liveness and Item Sync

## Context

The rolling playlist intentionally resolves at most two future capability URLs,
but a local watchdog treated eight seconds without telemetry as proof that IINA
had stopped. It finalized the current item and cleared CineLark's logical queue
while IINA kept playing the two URLs it already owned. The visible result was a
playlist that advanced only through those prepared items and then stopped.

Clearing coordinator state also detached later playlist events from their
episode metadata. Progress and stopped reports for those episodes were then
ignored. Progress reporting additionally waited for the ten-second periodic
batch after `fileLoaded`, so a newly activated episode was not guaranteed to
appear in provider playback state promptly.

## Change

- Treat telemetry silence as an availability signal, never as a terminal player
  event. Probe `player.requestState`, log continued silence, and preserve the
  session, logical queue, and item identities until an explicit ended, closed,
  stop, replacement, or IINA-termination event arrives.
- Upload progress as soon as each playlist item becomes active, then retain the
  existing periodic progress cadence.
- Keep every activated item addressable by playback ID until its own terminal
  event is processed. A next-item `fileLoaded` event must not make a delayed EOF
  event for the previous item ineligible for stopped reporting.
- Keep the two-future-item URL window. Refill it after each activation so the
  queue spans all remaining discovered episodes without resolving the whole
  series in advance.

## Validation

- Added a macOS unit-test target and a five-episode coordinator regression.
- The regression left a `player.requestState` probe unanswered, activated four
  successive items, observed both rolling refills, and passed.
- The same test delivered the next `fileLoaded` before the previous EOF and
  verified immediate progress uploads for episodes 1–4 plus stopped reports for
  episodes 1–3.
- `xcodebuild ... test` passed the macOS target, `swift test` passed 37 package
  tests, and the IINA plugin passed 18 Node tests.

## Current state

Implemented on 2026-08-25. Telemetry silence is non-terminal, the rolling queue
survives unanswered probes, and provider synchronization is item-scoped across
playlist transitions. The rolling playlist itself was subsequently superseded
by [006 — Sequential episode replacement](../006-sequential-episode-replacement/000-plan.md);
the non-terminal telemetry and per-item synchronization rules remain active.
