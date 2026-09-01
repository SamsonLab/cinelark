# 028 — Playback and Interaction Fidelity: Action

| | |
| --- | --- |
| **Status** | Implemented |
| **Completed** | 2026-08-28 |
| **Plan** | [000-plan.md](000-plan.md) |

## Outcome

Repeated playback, visible playback failure handling, and pre-TCA directional
interaction are restored on the current TCA/Profile/Emby ownership model. No
retired observable model or provider runtime was reintroduced.

## Implemented

- Queue authenticated `player.play` before waiting for `bridge.ready`, allowing
  the quiesced active IINA long poll to wake safely after a managed window
  closes. A timeout tears down the stale broker instead of leaving it pending.
- Keep playback in a preparing state until `player.fileLoaded`; expose localized
  failure, Retry, and Dismiss UI while retaining the exact failed request.
- Publish Remote playback only after IINA reports a loaded file, preventing a
  resolved Emby descriptor from appearing as active playback prematurely.
- Restore Home semantic navigation across hero actions, Continue Watching,
  Latest, library shelves, and View All, including section memory, scroll
  correction, and pointer-to-keyboard handoff.
- Restore Series detail navigation across Play, Favorite, seasons, episodes,
  Show More/Less, and people while routing activation into current Store
  actions.
- Restore episode focus clearance, full metadata rows, progress presentation,
  horizontal season/person scrolling, and UHDNow-era focus surfaces.
- Correct same-origin `/play/video/{asset}` delivery by moving its stripped
  `token` capability into the raw `Authorization` header, and set mpv's
  `force-media-title` so IINA presents the media title instead of the URL.

## Verification

- `swift test` in `packages/apple/CineLarkKit`: 71 passed, 0 failed.
- IINA plugin tests: 27 passed, 0 failed.
- macOS `xcodebuild test` with signing disabled: 47 passed, 0 failed.
- macOS `xcodebuild build` with signing disabled: succeeded.
- `git diff --check`: passed.

## Deviations and limits

- Automatic wake-up is safe only while the quiesced plugin still owns an active
  authenticated long poll. After a CineLark gateway replacement, IINA exposes
  no safe external wake hook for that released JavaScript context. The app now
  reports the failure and directs the user to the existing **Reconnect CineLark
  Bridge** menu action, after which Retry replays the retained request.
- A signed, real-account visual pass remains necessary to validate the complete
  online Emby + Keychain + IINA experience; isolated reducer, package, plugin,
  and unsigned application tests cover the changed contracts.

## Follow-up: direct-stream authorization

The reported `https://v1.uhdnow.com/play/video/{asset}` response was probed with
a bounded ranged request. `HEAD` returned 200, while the actual unauthenticated
`GET` returned 401 with a missing-authorization response. A synthetic regression
now covers moving the same-origin `token` query capability into `Authorization`.
That initial investigation did not establish that the provider route itself was
incorrect. Amendment 005 later restored it as the authoritative same-origin
target, and amendment 006 preserved its provider-issued query capability for
IINA compatibility. IINA Bridge 0.1.19 forces the
supplied media title before opening the URL and applies playback headers as
file-local native values.
