# 013 — Settings Information Architecture: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-26 | Consolidated application configuration in the native Settings scene | Local implementation |
| 2026-08-26 | Removed subsystem toolbar/sheet presentation and sidebar utilities | Local implementation |
| 2026-08-26 | Regenerated the Xcode project and ran the macOS suite | Local verification |

## Outcome & current state (as of 2026-08-26)

- `CineLarkSettingsView` provides four stable categories: General, Profiles &
  Sources, Remote, and Storage.
- General owns language, current version/build, update checks, and basic app
  identity.
- Profiles & Sources embeds the existing TCA Profile/Source stores, including
  source discovery, authentication, local-first import, and mirror settings.
- Remote pairing and paired-device management use the existing `RemoteFeature`.
  Entering/leaving the category starts and stops transient pairing state, and a
  Remote back command can still dismiss the presented Settings window.
- Storage retains Catalog/artwork accounting and safe purge behavior.
- The library sidebar contains only content destinations. Language and version
  utilities were removed; Refresh moved to the library toolbar and keeps its
  Command-R action.
- The main toolbar exposes one `SettingsLink` instead of separate Sources and
  Remote buttons. The standard application-menu Settings command remains
  available through macOS.
- `AppFeature.showsSourceManager` and its presentation actions were deleted.
  SwiftUI owns the Settings window; TCA continues to own profile/source intent
  and the stop-playback-before-switch rule.
- The playback-stop confirmation moved to the Settings scene, where the source
  or profile change originates.
- The validated ownership boundary is recorded as `L013` in
  `../010-tca-application-architecture/TCA-learn.md`.

## Validation

- `xcodegen generate` completed successfully and includes
  `CineLarkSettingsView.swift` in the application target.
- Unsigned `xcodebuild test` passes 16 Swift Testing tests across 9 suites and
  the existing 6 XCTest cases.
- Repository searches find no `showsSourceManager`, source-manager presentation
  action, separate Remote sheet state, or remaining `LanguageMenu` use.
- `git diff --check` passes.

## Deviations from plan

- No additional settings reducer was introduced. The Settings scene is a
  composition surface over existing scoped stores; adding presentation state
  would recreate the duplicate ownership this change removes.

## Open questions

- Pending initial CloudKit import now has a dedicated root recovery surface via
  [021 — Profile onboarding and sync health](../021-profile-onboarding-and-sync-health/001-action.md).
  Source configuration remains consolidated in Settings.
