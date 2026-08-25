# 008 — Safe IINA Plugin Lifecycle: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-25 |
| **Primary refs** | [`001-action.md`](001-action.md), `ManagedIINAPlaybackLauncher.swift`, `PlaybackCoordinator.swift` |
| **Related** | [`005.002`](../005-native-episode-playlist/002-iina-hot-reload-boundary.md), [`IINA integration`](../../docs/integrations/iina-plugin-api.md), `packages/apple/CineLarkKit/Sources/CineLarkPlayback/ManagedIINAPlaybackLauncher.swift` |

## Background

Stock IINA can retain callbacks from a replaced global JavaScript plugin. A
later callback can enter an IINA API after its weak native plugin owner has
been released, crashing IINA. CineLark already documents this restart boundary,
but its launcher still opens the bundled `.iinaplgz` for every missing,
outdated, or damaged installation. That asks a running IINA process to perform
the unsafe hot replacement.

The same launcher aborts the first playback immediately after opening IINA's
installer. Users must approve installation, understand the restart guidance,
and start playback again even when no previous plugin instance existed.

## Goals

- Never replace or repair the CineLark plugin while IINA is running.
- Preserve IINA's permission-consent UI for the first installation.
- Continue the original first-play request after the user approves and enables
  the plugin.
- Update or repair an existing CineLark plugin without invoking IINA's unsafe
  hot-reload path.
- Validate the bundled and installed plugin identity, version, and entry files
  before treating the integration as ready.
- Fail with an actionable message instead of crashing or silently launching a
  partially compatible playback path.

### Non-goals

- Patch or fork IINA's plugin runtime.
- Silently grant first-install plugin permissions.
- Force-terminate IINA or interrupt unrelated playback without user action.
- Manage plugins not owned by CineLark.
- Make plugin hot reload a supported development or production workflow.

## Design / Approach

### Installation state

Replace the current Boolean version check with explicit states: missing,
invalid, outdated, and current. The manifest identifier, semantic-numeric
version, `src/main.js`, and `src/global.js` are part of readiness.

### First installation

When the plugin is missing:

1. Start the authenticated CineLark bridge before opening the installer.
2. If IINA is already running, stop and tell the user to quit it before retrying.
3. Open the bundled `.iinaplgz` with IINA so IINA remains responsible for
   permission consent and initial enablement.
4. Wait for the installed plugin to connect and emit `bridge.ready`.
5. Continue the original `player.play` request without requiring a second click.

The wait is bounded. Cancellation, refusal, disabled plugins, and installer
failure remain visible failures rather than indefinite loading.

### Existing installation update or repair

Bundle an unpacked, signed-app-contained plugin directory in addition to the
`.iinaplgz`. When the installed plugin is outdated or invalid:

1. Refuse mutation while any IINA process is running.
2. Validate the bundled source as a current CineLark plugin.
3. Copy it to a staging directory beside IINA's plugin directory.
4. Atomically replace the existing CineLark plugin directory.
5. Validate the installed result, then launch a clean IINA process.

This preserves IINA's existing permission and enabled preferences because the
plugin identifier is unchanged and the user consented during first install.

### User-facing failures

Introduce a distinct update-boundary error telling the user to fully quit IINA
and retry. Do not open the installer, mutate files, or terminate IINA in this
state. Installation failure and post-install plugin unavailability remain
separate messages.

## Alternatives & decisions

- **Always open `.iinaplgz`: rejected.** It preserves IINA's UI but performs the
  known unsafe live replacement for updates and repairs.
- **Silently install everything from CineLark: rejected.** It would bypass
  IINA's first-install permission consent and enablement semantics.
- **Automatically terminate IINA: rejected.** A play request must not
  unexpectedly destroy unrelated playback. The safe boundary is explicit.
- **Ask users to reinstall manually: rejected as the primary path.** It leaves
  the known crash mechanism available and makes normal app/plugin version
  alignment operationally fragile.

## Amendments

- Updated 2026-08-25: Expanded the unsafe boundary from live replacement to
  application teardown after a stock-IINA crash showed a retained timer calling
  `http.get` during `NSApplication.terminate` — see
  [002-iina-termination-timer-boundary.md](002-iina-termination-timer-boundary.md).
