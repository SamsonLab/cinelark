# 017 — Emby Real-Contract Hardening: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-27 | Validated the read-only Emby v1 surface against a configured real service without persisting credentials or responses | [`000-plan.md`](000-plan.md) |
| 2026-08-27 | Added first-class episode identity and provider-count offset pagination | [`EmbyService.swift`](../../packages/apple/CineLarkKit/Sources/CineLarkEmby/EmbyService.swift) |
| 2026-08-27 | Added same-origin, secret-free direct-stream URL normalization | [`docs/integrations/emby.md`](../../docs/integrations/emby.md) |
| 2026-08-27 | Added synthetic real-shape resume and playback fixtures | [`CineLarkEmbyTests`](../../packages/apple/CineLarkKit/Tests/CineLarkEmbyTests) |

## Outcome & current state (as of 2026-08-27)

- `MediaKind.episode` preserves the exact item classification and locator from
  Emby resume results. Remote Profile import now retains episode playback state
  instead of dropping it or attributing it to a series.
- The Emby capability descriptor advertises movie, series, and episode item
  identities. The macOS library still presents movie and series only as
  top-level sections.
- Browse, works, and resume pagination advance by raw `Items.count`. An empty
  provider page before `TotalRecordCount` and any repeated cursor fail as an
  invalid response, preventing non-terminating imports.
- Direct-stream references resolve correctly for absolute, root-relative, and
  reverse-proxy-relative forms. Only same-origin HTTP(S) results are accepted.
- Playback descriptors remove credential-bearing query items, URL credentials,
  and fragments. The Emby account token is sent only through the separate
  `X-Emby-Authorization` header.
- Repository fixtures contain synthetic IDs, names, hosts, and secrets only.
  The private Postman collection and live account data remain outside the
  repository.

## Validation

- The initial focused test build failed because `MediaKind.episode` did not yet
  exist, confirming the episode regression test began red.
- `swift test --filter CineLarkEmbyTests`: 11 tests pass, including episode
  resume normalization, raw cursor advancement, non-progress rejection,
  reverse-proxy resolution, query-secret removal, and cross-origin rejection.
- `swift test --package-path packages/apple/CineLarkKit`: 63 tests pass across
  package domain, plugin, catalog, profile, insights, cache, playback, remote,
  and gateway targets.
- Unsigned `xcodebuild ... CODE_SIGNING_ALLOWED=NO test`: 28 Swift Testing tests
  across 11 suites and 6 XCTest cases pass.
- A read-only live check observed standard Emby responses for public server
  info, authentication, views, items, hierarchy, people, playback info, and
  artwork. A one-byte ranged direct-stream request returned HTTP 206 after the
  query credential was removed and only the Emby authorization header remained.
  No favorite, played-state, or playback-session mutation was sent.
- `git diff --check` passes.

## Deviations from plan

- Same-origin enforcement was made explicit after reviewing where playback
  headers are forwarded into IINA. This prevents a provider response from
  redirecting an account authorization header to another origin.
- The TCA learning archive was reviewed, but no entry was added: this milestone
  changed provider/domain contracts and did not expose a reusable TCA state,
  effect, navigation, dependency, or testing boundary.

## Open questions

- Original title, genres, series counts, and last-played timestamps are now
  implemented by the separate
  [metadata-fidelity milestone](../018-emby-metadata-fidelity/001-action.md).
- If a future Emby server requires a trusted cross-origin CDN, introduce an
  explicit origin-scoped playback credential contract instead of relaxing the
  same-origin authorization-header invariant.
- Add deterministic mock coverage for favorite, played-state, and check-in
  failures before changing those write paths; do not use a live account for
  destructive contract testing.
