# 006 — Playback Progress Synchronization

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-25 |
| **Primary refs** | `apps/macos/Sources/Models/PlaybackCoordinator.swift`, `apps/macos/Tests/PlaybackCoordinatorTests.swift` |
| **Related** | [000-plan.md](000-plan.md), [`docs/interfaces/playback-bridge.md`](../../docs/interfaces/playback-bridge.md) |

## Context

Playback progress currently crosses three independent asynchronous paths:
immediate upload after `player.fileLoaded`, coalesced ten-second position
uploads, and a terminal stopped upload. The timer reads the coordinator's
current mutable playback when it wakes, so a cancellation race can attribute an
old timer to a replacement episode. Terminal reporting is launched in a task,
which also leaves the old stopped write and the replacement episode's initial
progress write dependent on task scheduling order.

The file-loaded path must remain a single immediate upload while these paths are
reorganized. A failed stopped request currently still increments the observable
playback revision and refreshes Continue Watching, contrary to the bridge
contract.

## Required invariants

- Every queued write is an immutable snapshot of one playback ID and item.
- A periodic timer may flush only the playback ID that created it.
- `player.fileLoaded` queues exactly one immediate progress write.
- A completed item with a known duration reports that duration as its terminal
  position.
- The outgoing item's stopped write is reserved in the serial synchronization
  queue before a replacement can queue its initial progress write.
- Progress upload failures remain best effort. A stopped upload failure must not
  increment `playbackStateRevision` or invoke `onStoppedReported`.
- Telemetry silence remains non-terminal, and stale session events remain
  ignored.

## Approach

Convert active mutable state to a `PlaybackUpdate` snapshot at the coordinator
boundary. Inject the progress interval for deterministic tests, capture the
originating playback ID in each timer, and reject a stale timer before it can
clear or reuse a newer task.

Replace the chained-task reporter with one serial worker. It retains at most the
latest pending progress snapshot for a playback while the provider is slow, and
keeps stopped operations as ordering barriers. Reserving the stopped operation
is fast and does not block next-episode URL resolution or opening; its receipt
drives UI invalidation only after remote success.

App refresh callbacks are serialized separately from uploads. A manual content
replacement waits for the outgoing stopped upload, as before, but does not wait
for the Continue Watching network refresh. Logs correlate reservation, upload,
observable revision, and App refresh completion by playback ID.

## Validation plan

- Verify `fileLoaded` queues one progress write.
- Verify a cancelled old-episode timer cannot create or disturb a new-episode
  write.
- Verify the call order is old progress, old stopped, then replacement progress.
- Verify EOF clamps a near-terminal position to the known duration.
- Verify stopped failure leaves UI revision and callback unchanged.
- Run macOS target tests, CineLarkKit tests, and IINA plugin tests.

## Current state

Implemented on 2026-08-25. Live unified logs from manual and automatic episode
transitions showed the expected `fileLoaded → progress → EOF → stopped →
replacement fileLoaded` sequence, plus a window-close terminal path. The new
playback-ID-correlated logs now continue through synchronization reservation,
provider success/failure, observable revision, Continue Watching refresh, and
refresh completion.

The macOS target passes five coordinator/App regressions covering a five-episode
replacement sequence, stale timer isolation, slow-provider coalescing, terminal
failure semantics, duration clamping, and successful Continue Watching refresh.
CineLarkKit passes 37 tests and the IINA plugin passes 23 tests. No plugin source
or version change was required for this App-side synchronization change.
