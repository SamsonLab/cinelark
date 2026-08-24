# 005 — Native Episode Playlist: Plan

| | |
| --- | --- |
| **Status** | Superseded by [006 — Sequential episode replacement](../006-sequential-episode-replacement/000-plan.md) |
| **Anchor date** | 2026-08-24 |
| **Primary refs** | Pending |
| **Related** | [`docs/interfaces/playback-bridge.md`](../../docs/interfaces/playback-bridge.md), [`docs/architecture.md`](../../docs/architecture.md), [`docs/integrations/uhdnow-api.md`](../../docs/integrations/uhdnow-api.md) |

## Background

Episode continuation currently waits for a natural EOF event, reports stopped
progress to the provider, reloads the provider's series `nextUp` state, resolves
the next asset and capability URL, and sends another `player.play` command. The
serial cross-process and network path creates a visible gap and fails whenever
provider state propagation, asset resolution, or bridge reuse is delayed.

IINA exposes a native playlist API backed by mpv. It can advance to an already
queued URL without waiting for CineLark after EOF. UHDNow capability URLs are
short-lived and therefore must not be generated for an entire series in
advance.

## Goals

- Let IINA/mpv advance between queued episodes immediately after natural EOF.
- Maintain a logical queue across remaining seasons and episodes in CineLark.
- Keep a rolling window of at most two future capability URLs in IINA.
- Preserve independent playback IDs, progress, resume, and completion reporting
  for every episode.
- Keep movies and non-series episode playback behavior compatible.
- Cover queue creation, enqueueing, item transitions, and URL redaction with
  automated tests.

### Non-goals

- Persisting queues across app launches.
- Caching or refreshing capability URLs already handed to IINA.
- Adding an in-player episode browser or countdown overlay.
- Designing a new user-facing asset preference system. Automatic entries use
  the provider's first asset, matching existing automatic-next behavior.
- Proxying media through the bridge helper.

## Design / Approach

### Playback contract

`PlaybackDescriptor` remains one playable item with its own playback ID. The
launcher gains an enqueue operation that associates another descriptor with the
existing player session. The first descriptor's ID is the session ID for the
managed IINA player; later descriptors retain distinct playback IDs.

The `player.enqueue` bridge command contains the same opaque, redacted playback
fields as `player.play`. Player events include the active item playback ID in
their payload instead of relying on the envelope session ID.

### IINA ownership

The per-player plugin keeps an in-memory mapping from playlist URLs to playback
descriptors. `player.play` replaces the managed queue and opens its first item.
`player.enqueue` appends through `iina.playlist.add`. On `file-loaded`, the
plugin identifies the playing playlist item, selects its descriptor, applies
that item's resume position, and emits item-scoped events.

Natural EOF emits completion for the old item while mpv continues to the next
playlist item. Provider reporting never gates this transition. A delayed idle
fallback closes the overall player session only when no next item starts.

### CineLark rolling queue

After the selected episode starts, the coordinator loads all seasons and their
episode pages, orders them by season and episode number, and keeps only entries
after the selected episode. It resolves and enqueues entries until two future
items are ready. Each later `file-loaded` event consumes one ready entry and
triggers another refill.

Queue discovery and refill are bound to the first descriptor's session ID.
Results from a replaced or stopped session are discarded. Failures leave the
current item playable and are logged without terminating playback.

Completion reporting updates local recent-playback state synchronously, then
serializes provider stopped reports in the existing reporter actor without
blocking IINA's transition.

## Alternatives & decisions

- **Resolve every remaining URL up front:** rejected because capability URLs
  can expire before later episodes start and would widen token exposure.
- **Keep provider `nextUp` as the transition trigger:** rejected because it
  preserves the slow and failure-prone EOF round trip.
- **Proxy stable queue URLs through the helper:** deferred because it expands
  bridge security and streaming responsibilities without being required for a
  rolling window.
- **Queue only one next item:** valid, but two future items provide tolerance
  for one slow refill without materially increasing token lifetime risk.

## Amendments

- Updated 2026-08-24: documented the stock IINA 1.4.4 global-plugin hot-reload
  crash and made a full IINA restart an explicit post-install/update boundary
  — see [002-iina-hot-reload-boundary.md](002-iina-hot-reload-boundary.md).
- Updated 2026-08-24: corrected IINA playlist insertion to pass the append index
  explicitly through JavaScriptCore — see
  [003-explicit-playlist-append.md](003-explicit-playlist-append.md).
- Updated 2026-08-24: consolidated the IINA/JavaScriptCore lifecycle, security,
  queue-identity, watchdog, and real-EOF testing lessons — see
  [004-iina-plugin-engineering-lessons.md](004-iina-plugin-engineering-lessons.md).
- Updated 2026-08-25: telemetry silence must preserve the rolling queue, and
  every activated playlist item must upload progress immediately and retain
  item-scoped terminal reporting — see
  [005-telemetry-liveness-and-item-sync.md](005-telemetry-liveness-and-item-sync.md).
- Superseded 2026-08-25: native playlist enqueueing does not match the intended
  product behavior; continuation now replaces the current player content one
  episode at a time — see
  [006 — Sequential episode replacement](../006-sequential-episode-replacement/000-plan.md).
