# 028.005 — Provider-Declared Playback Target

## Context

An Emby-compatible UHD service advertises sources as both direct-playable and
direct-streamable while returning a same-origin `DirectStreamUrl` under its own
delivery route. CineLark amendment 003 ignored that target whenever
`SupportsDirectPlay` was true and synthesized the canonical Emby static stream
route instead.

Live contract validation showed that the provider-declared route is the
authoritative playable target. It returns byte-range Matroska content with the
account token supplied as a header. The query credential embedded in the API
response was initially treated as unnecessary. Amendment 006 later preserved
it for IINA/mpv compatibility while retaining ephemeral and redacted handling.

## Change

- Prefer a non-empty, same-origin HTTP(S) `DirectStreamUrl` for every source
  that advertises direct play or direct stream.
- Initially remove credential query items and supply the account token through
  the ephemeral `X-Emby-Token` header; amended by 006 to preserve an explicit
  provider query capability in parallel.
- Use the canonical static Emby stream route only when the provider omits its
  playback target.
- Preserve the source's advertised direct-play/direct-stream mode and selected
  media-source identity.

## Validation

- Replace the regression that rejected provider-specific direct-play targets
  with coverage that requires the sanitized provider route.
- Retain canonical fallback, cross-origin rejection, credential removal, and
  selected-variant coverage.
- Run CineLarkKit tests, macOS tests/build, IINA plugin tests, and
  `git diff --check`.

## Current state

Implemented. A bounded live contract check confirmed that the sanitized
provider-declared route returns byte-range Matroska content with the account
token supplied as a header. Validation completed with 73 CineLarkKit tests, 49
macOS Swift Testing tests, 6 macOS XCTest tests, and 28 IINA plugin tests
passing. Query-capability handling is amended by
[006-provider-query-capability.md](006-provider-query-capability.md).
