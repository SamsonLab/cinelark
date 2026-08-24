# 005.003 — Explicit Playlist Append

## Context

A real episode reached natural EOF and stopped even though CineLark had prepared
nine remaining logical queue entries. The initial plugin test mocked
`playlist.add(url)` as an append and therefore did not model IINA's JavaScriptCore
bridge accurately.

IINA 1.4.4 exports the Swift method `add(_ url: JSValue, _ at: Int = -1)` through
`JSExport`. The Swift default argument is not applied to JavaScript calls.
Omitting `at` converts the missing value to integer `0`, so each future episode
was inserted before the playing entry. After two inserts, the current episode
was the last playlist item and mpv correctly stopped at EOF.

## Change

- Call `playlist.add(entry.url, -1)` to append every future episode explicitly.
- Model IINA's missing-integer behavior in the plugin harness: an omitted index
  inserts at zero instead of appending.
- Require plugin version 0.1.9 so an installed 0.1.8 cannot silently retain the
  broken insertion behavior.

## Validation

- Added a regression test whose mock matches JavaScriptCore's missing-integer
  conversion. It failed while the plugin called `playlist.add(url)` and passed
  after the explicit `-1` argument was added.
- Replaced placeholder playlist data with a sanitized fixture captured from a
  real UHDNow API response for adjacent S01E02 and S01E03 episodes. The fixture
  retains observed episode IDs, asset IDs, codec, resolution, duration, host,
  route, and capability-token query shape while replacing the secret value with
  `<redacted>` and omitting HTTP credentials entirely.
- `npm test && npm run package` passed 18 plugin tests and produced the 0.1.9
  plugin archive.
- `swift test` passed 37 tests and
  `cargo +1.95.0 test --locked --manifest-path
  packages/rust/cinelark-bridge/Cargo.toml` passed 11 tests.
- A macOS Debug build completed with `BUILD SUCCEEDED` in an isolated temporary
  DerivedData directory so it did not replace the running bridge helper.
- Installed plugin 0.1.9 while IINA was fully quit and verified the installed
  `global.js` and `main.js` hashes match the packaged sources.
- Verified from IINA 1.4.4 source and its Open URL UI that saved HTTP credentials
  match an exact host and port and are injected only by that window. The user's
  Passwords.app website entry was not interchangeable with IINA's own saved
  item. A tokenless VOD request still failed after HTTP authentication, proving
  that the provider-issued capability token remains required.
- Observed IINA 1.4.4 copy a failed HTTP-authenticated URL, including userinfo,
  back into its visible URL field. The exposed credential must be rotated; this
  UI flow is no longer an acceptable automated smoke-test path.
- Replaced the original four-second telemetry-silence finalization with an
  interim request-state probe and second timeout. The later correction in
  [005](005-telemetry-liveness-and-item-sync.md) removed timeout-driven
  finalization entirely.
- Executed the live smoke test with real E2/E3/E4 API data and capability URLs.
  CineLark discovered nine future episodes and enqueued two within one second.
  E2 was moved to five seconds before EOF and the user confirmed the automatic
  transition behavior in stock IINA 1.4.4.

## Current state

Plugin 0.1.9 appends future episodes with an explicit `-1` index. Unit mocks use
the actual IINA insertion contract and realistic sanitized UHDNow series data.
The installed plugin is 0.1.9. Installation or update still requires a full IINA
restart before live playback. Telemetry silence is non-terminal as of
[005](005-telemetry-liveness-and-item-sync.md). Application continuation no
longer uses playlist enqueueing as of
[006](../006-sequential-episode-replacement/000-plan.md).
