# 006.005 — Replacement Lifecycle Isolation

## Context

The live 0.1.13 trace first detected EOF correctly and dispatched a replacement
`player.play` to the existing managed player. About 125 ms later, IINA delivered
the previous file's remaining end callbacks before the replacement file loaded.
The per-player plugin had already assigned the new session as active, so it
emitted `player.ended(reason=eof)` for an episode that had never loaded. The
coordinator then resolved another episode, while `player.closed` cleared the
global managed-player reference. Subsequent commands created new windows and
produced a cascade of skipped episodes.

Manual replacement does not exhibit this behavior. A second in-app play action
sends `player.stop` to the current session before sending the next
`player.play`, and the global plugin posts that command to the same managed
player ID.

## Change

- Make automatic continuation send `player.stop` for the completed session,
  then `player.play` for the replacement, matching manual in-app playback.
- Keep the outgoing session authoritative until the replacement emits
  `iina.file-loaded`. Pause, EOF-property, end-file, and completion-poll paths
  cannot terminate an incoming session before that point.
- Treat a window close during replacement loading as a failed replacement and
  report it against the incoming session, rather than leaving a dead player
  reference.
- Never create a second player as an acknowledgement-timeout fallback for a
  replacement command. Report a bridge error and preserve the same-player
  invariant; only an explicit later play with no managed player may create one.

## Validation

- `npm test --prefix plugins/iina` passed 23 tests. The completion regression
  injects pause, `eof-reached`, and end-file callbacks after replacement
  `core.open` but before the next `file-loaded`; the incoming episode emits no
  terminal event until it loads and later reaches its own final frame.
- The global-plugin regression lets the 500 ms replacement acknowledgement
  timeout expire and verifies only one `createPlayerInstance` call occurred.
- `swift test --package-path packages/apple/CineLarkKit` passed 37 tests.
- The macOS Xcode target passed its five-episode replacement test. It verified
  four automatic `player.stop` commands target episodes 1–4 before the four
  replacement opens, with zero enqueue calls.
- Packaged the current plugin 0.1.15 as `plugins/iina/dist/CineLark.iinaplgz`;
  SHA-256 is
  `54ae3783d694f448299bdb3384124d6c1a6055d71c5cccd0be31cc9863bb1199`.
- A live IINA reproduction remains pending installation and full restart of
  plugin 0.1.15.

## Current state

First implemented in plugin 0.1.14 on 2026-08-25 from the 01:17 live trace and
retained in 0.1.15 with a 500 ms completion-poll cadence. An episode cannot end
before its own `player.fileLoaded`, and an automatic replacement cannot silently
fall back to a new IINA player window.
