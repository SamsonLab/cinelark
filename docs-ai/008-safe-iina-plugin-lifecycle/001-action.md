# 008 — Safe IINA Plugin Lifecycle: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-25 | Added playback preparation before provider capability URL creation | Working tree |
| 2026-08-25 | Added explicit missing, invalid, outdated, and current plugin states | Working tree |
| 2026-08-25 | Preserved IINA consent for first install and continued the pending play after `bridge.ready` | Working tree |
| 2026-08-25 | Replaced stopped outdated or invalid installations from a validated bundled directory | Working tree |
| 2026-08-25 | Added actionable setup-boundary and installation-failure messages | Working tree |
| 2026-08-25 | Quiesced plugin timers before IINA releases their native API owner | [`002-iina-termination-timer-boundary.md`](002-iina-termination-timer-boundary.md) |

## Outcome & current state (as of 2026-08-25)

CineLark prepares the IINA integration before requesting a provider playback
URL. A setup failure therefore cannot consume or leave behind a short-lived
media capability.

The launcher validates the installed plugin identifier, numeric version, and
both JavaScript entry files. A current installation proceeds normally. A
missing installation starts the authenticated bridge, opens IINA's official
`.iinaplgz` consent flow, waits up to 90 seconds for a compatible
`bridge.ready`, and then continues the original play request.

An outdated or invalid installation is never handed to IINA's live installer.
While IINA is fully stopped, CineLark validates the unpacked plugin bundled in
its signed app, copies it to a sibling staging directory, atomically replaces
the installed directory, and validates the result. If IINA is running,
CineLark performs no mutation and asks the user to quit it before retrying.
CineLark does not force-terminate IINA.

Bridge readiness now includes the plugin version. Events from missing,
malformed, or older plugin versions cannot satisfy launch readiness. Concurrent
play requests share one preparation task instead of opening duplicate consent
flows or racing installation mutations.

Plugin 0.1.17 also treats managed-player window teardown as a native API
boundary. The player synchronously notifies the global entry before returning
from `iina.window-will-close`; both entries cancel their registered timers, and
callbacks that already raced past cancellation check a quiesced flag before
touching IINA. An authenticated play command already waiting in the current
long poll may reactivate the bridge after an ordinary window close.

## Validation

- `swift test` passed all 41 CineLarkKit tests.
- `xcodebuild -project apps/macos/CineLark.xcodeproj -scheme CineLark -destination
  'platform=macOS' CODE_SIGNING_ALLOWED=NO test` passed all 11 macOS tests.
- `npm test --prefix plugins/iina` passed all 26 plugin tests.
- Plugin tests cover missing, malformed, invalid, outdated, current, and newer
  installations; validated replacement; and rejection without overwriting the
  existing installation.
- The coordinator regression verifies preparation failure requests zero
  provider playback URLs.
- The built app resolves both `CineLark.iinaplgz` and
  `CineLark.iinaplugin`; the unpacked `Info.json` and `src` tree match the
  repository plugin at version 0.1.17.
- Both localized `.strings` files pass `plutil -lint`.

## Deviations from plan

None.

## Open questions

- Exercise the first-install consent-and-auto-continue path with a disposable
  IINA profile or after the user intentionally removes the working plugin.
- Reproduce a full IINA quit with plugin 0.1.17 installed and playback active;
  automated tests cover timer cancellation and callbacks racing teardown, but
  cannot reproduce AppKit's native plugin-deallocation order.
