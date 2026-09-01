# 028.003 — Emby Direct-Play Target

## Context

Some Emby-compatible servers return a provider-specific `DirectStreamUrl`, for
example `/play/video/{asset}`, even when a source also advertises
`SupportsDirectPlay`. CineLark previously preferred that value. The UHD delivery
route requires an authorization token and returned `missing authorization
token` when opened without a valid player header.

The descriptor also included the comma-delimited `X-Emby-Authorization` value.
IINA/mpv represents `http-header-fields` as a comma-delimited list, so a header
whose value contains commas is not a safe player transport contract.

## Change

- Resolve a direct-play source through the canonical
  `Videos/{itemId}/stream?static=true&MediaSourceId={sourceId}` endpoint.
- Use `X-Emby-Token` for playback transport instead of the compound
  `X-Emby-Authorization` header.
- Consult a provider `DirectStreamUrl` only for direct-stream-only sources.
- Continue removing credential query items from direct-stream URLs and forward
  any delivery token as a header.

## Validation

- Add a regression where a direct-play source advertises the UHD-style
  `/play/video/{asset}` path and assert that it is ignored.
- Retain direct-stream-only same-origin, cross-origin, and token-sanitization
  coverage.
- Run CineLarkKit tests, macOS tests/build, IINA plugin tests, and
  `git diff --check`.

## Current state

Superseded by
[005-provider-declared-playback-target.md](005-provider-declared-playback-target.md).
The canonical route remains only as a fallback when `PlaybackInfo` omits a
provider-declared target.
