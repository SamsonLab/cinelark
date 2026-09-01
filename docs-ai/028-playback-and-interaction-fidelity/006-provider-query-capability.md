# 028.006 — Provider Query Capability

## Context

The selected Emby-compatible source returns a same-origin `DirectStreamUrl`
with a provider-issued query credential. Header-only ranged requests succeed in
an HTTP client, but IINA/mpv does not load the media reliably through the same
route even when the account token is applied as a file-local header.

The service accepts its declared query capability and continues to return
byte-range Matroska content. Removing that capability therefore changes the
provider's playback contract without improving interoperability.

## Change

- Preserve provider-issued query items on a validated same-origin HTTP(S)
  `DirectStreamUrl`, including its playback capability.
- Continue supplying `X-Emby-Token` as a file-local IINA header and map an
  explicit provider `token` to `Authorization` as before.
- Keep the resulting URL ephemeral: it must not enter reducer state, Catalog,
  Profile, fixtures containing real data, or diagnostic output.
- Continue rejecting user info, fragments, cross-origin references, and
  non-HTTP(S) targets before forwarding any account credential.

## Validation

- Replace query-removal assertions with synthetic provider-capability
  preservation coverage for direct-play and direct-stream sources.
- Retain cross-origin rejection, canonical fallback, source selection, and
  file-local IINA header coverage.
- Run CineLarkKit tests, macOS tests/build, IINA plugin tests, and
  `git diff --check`.

## Current state

Implemented. Live bounded ranged checks confirmed that the provider accepts its
declared query capability, a `token` query alias, and header authentication,
each returning byte-range Matroska content. CineLark now preserves the exact
provider-declared query on the ephemeral IINA URL while continuing file-local
header authentication. Validation completed with 73 CineLarkKit tests, 49
macOS Swift Testing tests, 6 macOS XCTest tests, and 28 IINA plugin tests
passing. The full macOS test build and whitespace validation also passed.
