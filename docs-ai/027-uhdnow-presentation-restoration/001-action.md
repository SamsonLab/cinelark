# 027 — UHDNow Presentation Restoration: Action

| | |
| --- | --- |
| **Status** | Implemented |
| **Completed** | 2026-08-28 |
| **Plan** | [000-plan.md](000-plan.md) |

## Outcome

The mature UHDNow information hierarchy and interaction patterns now sit on top
of the current TCA, personal Profile, CloudKit, and media-source architecture.
No retired provider, navigation, or state owner was restored.

## Implemented

- Restored the cinematic Home hero, Continue Watching, Latest, and keyed
  per-library shelves. Resume actions preserve the personal Profile position.
- Restored complete Series detail behavior: primary episode selection, season
  navigation, episode rows, progress, direct playback, and cast/crew links.
- Restored the Movies and Series category controls, collection paging,
  media Favorites, and Person detail presentation with keyboard/pointer focus.
- Reused existing poster, backdrop, filter, artwork, focus, and glass controls
  instead of introducing a parallel presentation system.
- Unified General, Viewing & Sources, Remote, and Storage settings with shared
  page headers and cards. The single personal Profile, automatic iCloud sync,
  and online/local Emby setup remain backed by their existing reducers and
  clients.
- Kept sidebar selection-driven and route destinations Store-driven, preserving
  the navigation-stack integration invariant.

## Verification

- `swift test` in `packages/apple/CineLarkKit`: 70 passed, 0 failed.
- macOS `xcodebuild test` with signing disabled: 52 passed, 0 failed, 0 skipped.
- macOS `xcodebuild build` with signing disabled: succeeded.
- `git diff --check`: passed.
- Launched the Debug app with an in-memory Profile repository and inspected the
  Settings and Emby setup surfaces through macOS accessibility state. The page
  hierarchy, empty source state, server URL/display name inputs, verification,
  and cancellation controls were present and usable.

## Deviations and limits

- Person favorites were not added because the current personal Profile contract
  stores media favorites only. Adding a second implicit favorite model would
  violate the architecture-preservation goal.
- A populated online Emby Home/detail visual pass still requires a correctly
  signed app with the user's real source and CloudKit entitlements. Reducer,
  package, and application tests cover the restored data and routing behavior;
  the ad-hoc validation process intentionally used isolated Profile state.
