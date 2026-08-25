# 008.002 — IINA Termination Timer Boundary

## Context

A stock IINA 1.4.4 crash on 2026-08-25 occurred 33 ms after AppKit entered
`NSApplication.terminate`. The main-thread stack was
`JavascriptPolyfill.callJSCallback` → the CineLark global callback →
`JavascriptAPIHttp.get`. IINA had already released the plugin instance owned by
the HTTP API, so its weak `pluginInstance` trapped when the retained native
timer fired.

This corrects the earlier assumption that only installation hot reload was
unsafe. IINA teardown also releases the JavaScript plugin owner before all
polyfill timers are guaranteed to be invalidated.

## Change

- Track every CineLark timeout and interval created through IINA's timer
  polyfill.
- Have the managed-player plugin synchronously signal its global instance from
  `iina.window-will-close`, which IINA emits while the plugin owner is still
  valid during application termination.
- Quiesce global transport work and clear pending timers before the window-close
  callback returns.
- Make callbacks scheduled before quiescence pure no-ops; they must never enter
  an IINA API after the boundary.
- Keep an already-issued long poll available for a subsequent play after an
  ordinary player-window close. Only an authenticated `player.play` response or
  the explicit reconnect menu action may resume transport. Empty responses and
  errors do not create a new timer after quiescence.
- Start the final `player.closed` HTTP request synchronously on the window-close
  callback's main-run-loop turn, before quiescing the global entry. Its promise
  callbacks are pure JavaScript and never enter another IINA API.
- Apply the signal only to CineLark-managed players; closing an ordinary IINA
  window must not disable the bridge.

## Validation

- The two new teardown regressions failed before implementation: the global
  message was absent, and the managed-player interval remained active.
- `npm test --prefix plugins/iina` passes all 26 tests after implementation.
- The regression harness forcibly invokes callbacks captured before teardown
  after their timers have been cleared; neither callback reaches HTTP, player,
  logging, or message APIs.
- A separate regression confirms that ordinary IINA windows do not quiesce the
  bridge.
- Native AppKit termination with plugin 0.1.17 remains a manual smoke test.

## Current state

Implemented in plugin 0.1.17. CineLark requires that version before accepting
`bridge.ready`.
