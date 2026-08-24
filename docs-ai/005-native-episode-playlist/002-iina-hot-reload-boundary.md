# 005.002 — IINA Hot-Reload Boundary

## Context

The first manual installation of plugin 0.1.8 crashed stock IINA 1.4.4 about
nine seconds after launch. The main-thread stack ended in
`JavascriptAPIHttp.request`, entered from `JavascriptPolyfill.callJSCallback`
through a Foundation timer.

Inspection of IINA 1.4.4 and the installed binary showed that the trap is the
nil branch for the HTTP API's weak `pluginInstance`. IINA had replaced the
global plugin instance during installation, but a timer retained by the old
JavaScript polyfill still fired and attempted the next broker request. The
failure occurs before any managed-player or playlist operation.

## Change

- Treat IINA plugin installation and update as a process restart boundary.
- Tell the user to fully quit and reopen IINA before retrying playback.
- Record the IINA 1.4.4 lifecycle limitation in the integration source of
  truth. Do not attribute this crash to `player.enqueue` or native mpv playlist
  advancement.
- Keep plugin version 0.1.8 unchanged because the installed plugin payload is
  correct and a cleanly launched instance does not reproduce the trap.

## Validation

- Confirmed the crash report's failing path is a main-run-loop timer calling
  `JavascriptAPIHttp.get`, not a playlist API.
- Confirmed the installed plugin is version 0.1.8 and its `global.js` matches
  the repository payload.
- Observed the cleanly relaunched IINA 1.4.4 process remain alive for more than
  five minutes, including multiple three-second bridge retry intervals.

## Current state

Automatic episode continuation remains implemented through the rolling native
playlist. After any Bridge installation or update, IINA must be fully restarted
before the playback path is considered valid. A source-level fix belongs in
IINA's plugin lifecycle cleanup; plugin JavaScript cannot reliably detect that
its native weak owner has already been replaced. Plugin 0.1.9 was subsequently
required by [003-explicit-playlist-append.md](003-explicit-playlist-append.md);
the restart boundary still applies to that and later updates.
