# 006 — Sequential Episode Replacement: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-25 |
| **Primary refs** | Pending |
| **Related** | [005 — Native episode playlist](../005-native-episode-playlist/000-plan.md), [`docs/interfaces/playback-bridge.md`](../../docs/interfaces/playback-bridge.md), [`docs/architecture.md`](../../docs/architecture.md) |

## Background

The native-playlist design keeps two future capability URLs in IINA and refills
the window after each transition. That implementation is technically rolling,
but it exposes future episodes as playlist entries and makes IINA's playlist the
owner of continuation. The intended product behavior is different: the player
should contain one episode, and natural EOF should replace that content with the
next episode.

## Goals

- Keep exactly one CineLark episode as the managed player's active content.
- On natural EOF, resolve the next episode and send a new `player.play` command
  that reuses the managed IINA window and calls `core.open` for the new URL.
- Continue across every remaining ordered episode without `player.enqueue`.
- Preserve per-episode progress, stopped reporting, resume position, and
  Continue Watching invalidation.
- Keep telemetry silence non-terminal.

### Non-goals

- Preloading future URLs into IINA.
- Removing `player.enqueue` from protocol compatibility in this change.
- Eliminating the network gap needed to resolve the next asset and capability
  URL after EOF.
- Persisting the remaining episode order across app launches.

## Design / Approach

CineLark discovers the remaining episode metadata in the background but does
not resolve or enqueue any future playback URL. On natural EOF, it finalizes and
reports the completed item, takes the next metadata candidate, resolves its
asset and capability URL, creates a new playback descriptor, and calls the
launcher's existing `open` operation.

The bridge already supports replacing an active managed session: the global
plugin forwards a new `player.play` command to the existing player instance,
and the per-player plugin calls `core.open`. The descriptor ID becomes the new
session ID while the IINA window is reused.

Replacement work is guarded by the previous session ID. Explicit stop, manual
replacement, or close invalidates an in-flight next-episode resolution before a
new URL can open.

## Alternatives & decisions

- **Keep a rolling native playlist:** rejected because the playlist contents
  and ownership do not match the requested single-content player model.
- **Pre-resolve one hidden next URL:** rejected because capability URLs are
  short-lived and the current episode may play for a long time.
- **Create a new IINA window for every episode:** rejected because the existing
  managed-player reuse path can replace content without window churn.

## Amendments

- Updated 2026-08-25: Stock IINA does not pass mpv event detail objects to
  generic JavaScript plugin callbacks, so EOF detection now observes the
  `eof-reached` property and records end-to-end bridge diagnostics — see
  [002-stock-iina-eof-detection.md](002-stock-iina-eof-detection.md).
- Updated 2026-08-25: Live diagnostics showed IINA closing the managed window
  at EOF before emitting an observable terminal event; managed playback now
  enables mpv `keep-open` and classifies terminal-position window closure as an
  EOF fallback — see [003-keep-managed-player-open.md](003-keep-managed-player-open.md).
- Updated 2026-08-25: Because stock IINA can reach its final decoded frame and
  close without exposing pause or EOF callbacks, the player now polls playback
  progress and emits EOF immediately when it observes completion — see
  [004-completion-progress-polling.md](004-completion-progress-polling.md).
- Updated 2026-08-25: Live 0.1.13 logs showed old-media EOF callbacks being
  attributed to an incoming replacement session, causing cascading episode
  opens and new windows. Automatic continuation now uses the same stop-then-play
  sequence as manual replacement and isolates lifecycle events until the new
  file loads — see
  [005-replacement-lifecycle-isolation.md](005-replacement-lifecycle-isolation.md).
- Updated 2026-08-25: Progress synchronization is now scoped to immutable
  playback snapshots. Periodic writes are bound to their originating playback
  ID, completed items report their known duration, and a completed item's
  stopped write is reserved before the replacement episode can enqueue its
  initial progress — see
  [006-playback-progress-synchronization.md](006-playback-progress-synchronization.md).
