# 028 — Playback and Interaction Fidelity: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-28 |
| **Primary refs** | `PlaybackFeature.swift`, `ManagedIINAPlaybackLauncher.swift`, `CatalogLibraryViews.swift`, `CatalogMediaDetailView.swift` |
| **Related** | [Keyboard-first navigation](../003-keyboard-first-navigation/000-plan.md), [Safe IINA lifecycle](../008-safe-iina-plugin-lifecycle/000-plan.md), [TCA architecture](../010-tca-application-architecture/000-plan.md), [UHDNow presentation restoration](../027-uhdnow-presentation-restoration/000-plan.md) |

## Background

The presentation restoration recovered major Home and detail hierarchy, but it
did not restore the complete pre-TCA semantic focus graphs. Runtime evidence
also shows playback reaching `Preparing player.play` without reaching
`bridge.ready`, `Queued player.play`, or `fileLoaded` after the managed IINA
window has previously closed. Playback failure state is not presented in the
application window, making the bridge timeout appear as an inert button.

The interaction reference is the application immediately before the TCA media
source migration (`e9ec38f^`). Its UI and keyboard behavior must be ported onto
the current Store-driven state instead of restoring retired observable models.

## Goals

- Make repeated playback reliable across managed-player close, and provide an
  explicit recovery path after CineLark gateway replacement, without weakening
  the IINA termination crash boundary.
- Present preparation, failure, retry, and active playback truthfully.
- Restore explicit arrow-key focus graphs for Home and series detail, including
  pointer-to-keyboard handoff, section memory, scrolling, and activation.
- Restore the pre-TCA series detail hierarchy: hero actions, season strip,
  complete episode rows, expansion control, and cast navigation.
- Preserve TCA navigation, one personal Profile, local-first playback facts,
  CloudKit sync, authenticated artwork, and the standard Emby runtime.

### Non-goals

- Do not restore `AppModel`, `MediaDetailModel`, playback option ownership, or
  the retired private UHDNow provider.
- Do not introduce geometry-derived focus traversal or parallel navigation
  state outside the existing `ShortcutCoordinator` surface stack.
- Do not make IINA plugin API calls from callbacks after its teardown boundary.

## Design / Approach

### Playback recovery

Keep teardown callbacks quiescent, but allow a later, authenticated broker
command to re-arm transport through a safe discovery path owned by the global
plugin lifetime. Add a regression that covers gateway replacement after a
managed window closes. Model playback as preparing until `fileLoaded`; surface
normalized failures with retry and dismissal actions.

### Directional navigation

Port the model-backed Home and detail focus sections from `e9ec38f^` onto
current snapshots and Store actions. Stable IDs identify hero actions,
Continue Watching entries, shelves, seasons, episodes, expansion, and people.
Each destination remembers its last valid target and scrolls the selected
semantic anchor into view.

### Series detail

Use current `MediaDetailFeature` state as the sole source of detail, seasons,
episodes, Profile state, and playback delegates. Reuse pre-TCA composition and
shared focus presentation while retaining current authenticated artwork and
route links.

## Verification

- Add an IINA global-plugin regression for authenticated playback wake-up from
  the active post-close broker poll.
- Add reducer tests for playback preparation/failure/retry state and episode
  selection where behavior changes.
- Run IINA plugin tests, CineLarkKit tests, macOS tests, unsigned build, and
  `git diff --check`.
- Exercise repeated playback and directional Home/series-detail navigation in
  the running app when the signed local runtime permits it.

## Alternatives & decisions

- Automatically terminating IINA on bridge failure is rejected because it is
  destructive to unrelated player sessions.
- Removing teardown quiescence is rejected because it reopens the verified
  IINA JavaScript timer use-after-release crash.
- Relying on native SwiftUI focus traversal is rejected because it does not
  preserve section semantics, pointer handoff, or stable scroll origins.

## Amendments

- Updated 2026-08-29: Provider-issued query capabilities on a validated
  same-origin `DirectStreamUrl` are preserved for IINA/mpv compatibility while
  remaining ephemeral and redacted. Header authentication continues in
  parallel — see
  [006-provider-query-capability.md](006-provider-query-capability.md).

- Updated 2026-08-28: Provider-declared same-origin `DirectStreamUrl` is now
  authoritative for playable Emby sources; the canonical static stream route
  is only a fallback when the provider omits a target. This corrects the
  provider-route rejection introduced by amendment 003 — see
  [005-provider-declared-playback-target.md](005-provider-declared-playback-target.md).

- Updated 2026-08-28: Authenticated playback headers are now applied as
  file-local mpv options with the native string-array representation, and a
  bounded startup watchdog prevents unresolved IINA loads from remaining in
  `preparing` indefinitely — see
  [004-authenticated-file-load.md](004-authenticated-file-load.md).

- Updated 2026-08-28: Emby direct-play resolution now rejects provider-specific
  `DirectStreamUrl` routes for sources that advertise direct play, uses the
  canonical static Emby stream endpoint, and supplies player-safe token headers
  — superseded by
  [005-provider-declared-playback-target.md](005-provider-declared-playback-target.md);
  see [003-emby-direct-play-target.md](003-emby-direct-play-target.md) for the
  original change.

- Updated 2026-08-28: Detail playback now separates the primary resume action
  from explicit movie and episode version selection. Provider-neutral playback
  variants preserve the pre-TCA UHDNow selection panel while Emby remains the
  runtime owner — see
  [002-detail-hierarchy-and-playback-variants.md](002-detail-hierarchy-and-playback-variants.md).

- 2026-08-28: Gateway replacement recovery was narrowed from automatic wake-up
  to a precise IINA menu recovery instruction. Once teardown quiesces a plugin
  whose old long poll has also been destroyed, no supported external IINA API
  can safely invoke that JavaScript context. Active authenticated long polls do
  wake automatically; replaced gateways fail visibly and retain a Retry action.
