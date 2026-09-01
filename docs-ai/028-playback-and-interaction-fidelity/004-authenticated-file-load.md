# 028.004 — Authenticated File Load

## Context

Live validation of an episode with two Emby media sources showed that both
sources advertise direct play and that the canonical stream endpoint returns a
signed redirect to byte-range MKV content. CineLark resolved that endpoint, but
IINA never emitted `player.fileLoaded`.

That check established endpoint reachability, not which playback target the
provider intended. Amendment 005 restores the sanitized provider-declared
`DirectStreamUrl` as authoritative and retains the canonical route as fallback.

The IINA plugin wrote `http-header-fields` as one global comma-delimited string.
IINA's supported plugin pattern writes
`file-local-options/http-header-fields` as an array of individual header lines.
The old representation did not reliably attach `X-Emby-Token` to the file load,
so the authenticated stream request could fail before mpv opened media.

The application also had no deadline between a successfully queued
`player.play` command and `player.fileLoaded`, leaving UI in `preparing` when a
player load failed silently or the global plugin was already quiescent.

## Change

- Apply playback headers through `file-local-options/http-header-fields` using
  one array element per header.
- Keep headers scoped to the current file and credentials out of logs, real-data
  fixtures, and persistent state. Amendment 006 permits a provider-issued query
  capability only on the ephemeral playback URL.
- Add a reducer-owned startup watchdog after the bridge accepts `player.play`.
  Cancel it on `player.fileLoaded`; on expiry, clear phantom active playback and
  retain the exact request for Retry.
- Bump the IINA plugin compatibility floor so the unsafe header representation
  cannot be treated as current.

## Validation

- Add an IINA plugin regression for the exact file-local header property and
  array representation.
- Add a reducer regression for startup timeout and cancellation on file load.
- Run IINA plugin tests, CineLarkKit tests, macOS tests/build, and
  `git diff --check`.

## Current state

Implemented. The IINA plugin now applies authenticated playback headers as
file-local native values before opening media, and CineLark fails a queued load
after 20 seconds when no matching `player.fileLoaded` arrives. Validation
completed with 28 IINA plugin tests, 73 CineLarkKit tests, 49 macOS Swift
Testing tests, and 6 macOS XCTest tests passing.
