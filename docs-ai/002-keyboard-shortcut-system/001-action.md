# 002 — Keyboard Shortcut System: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-21 | Added the global shortcut coordinator, hold-to-reveal state, target registration, and glass badges. | Working tree |
| 2026-08-21 | Registered visible interactive controls across Home, collections, favorites, search, details, and playback options. | Working tree |
| 2026-08-21 | Reduced permanent navigation ownership to `Command-1...5`, moved refresh to `Command-R`, and returned `Command-6...9` to the dynamic pool. | Working tree |
| 2026-08-21 | Changed dynamic allocation to a per-reveal snapshot and prevented mid-display renumbering. | Working tree |
| 2026-08-21 | Added input submission, Escape behavior, stack back commands, and swipe-back handling. | Working tree |
| 2026-08-21 | Replaced dynamic numeric allocation with arrow-key selection, Return activation, and a non-layout overlay; reduced Command hold to one second. | [Follow-up](002-directional-focus-simplification.md) |
| 2026-08-21 | Built the Debug app and exercised the reliable automation paths in the running app. | Working tree |

## Outcome & current state (as of 2026-08-21)

`apps/macos/Sources/Views/Components/ShortcutSystem.swift` contains the shared
fixed shortcut vocabulary, coordinator, directional routing, and overlay badges.

`apps/macos/Sources/App/CineLarkApp.swift` owns and injects one coordinator.
`apps/macos/Sources/Views/LibraryView.swift` binds fixed navigation, refresh,
navigation-stack back behavior, and sidebar badges. The fixed commands are
dispatched by the coordinator so they work independently of sidebar focus.

Dynamic media grids expose arrow-key movement with a shared focus outline and
Return activation. They no longer register per-control geometry or consume a
numeric shortcut pool. Language selection and other state-dependent controls do
not own permanent shortcuts.

`apps/macos/Sources/Views/SearchView.swift` owns Return submission and contextual
Escape clearing. Backspace, `Command-[`, `Command-Left`, and horizontal swipe
events delegate to the current navigation-stack back action when text input and
modal presentation do not own the event.

## Validation

- `xcodebuild -project apps/macos/CineLark.xcodeproj -scheme CineLark
  -configuration Debug -destination 'platform=macOS' build` succeeded.
- In the rebuilt running app, `Command-2` selected Movies and `Command-5`
  selected Search.
- `Command-1` returned from a Home media detail to the Home root even though the
  selected sidebar section did not change.
- Backspace returned from media detail to Home.
- Escape cleared a non-empty Search field while retaining field focus.
- In Movies, the initial poster had a visible focus outline, Right moved it to
  the next poster, and both Return and Space opened that selected poster's
  detail screen.
- `git diff --check` reported no whitespace errors after implementation.

## Deviations from plan

This record was introduced after shortcut implementation had already begun in
the working tree because CineLark did not yet have `docs-ai/` governance. The
chronology above is intentionally not presented as plan-first.

The initial shortcut proposal reserved `Command-1...7` and began dynamic
allocation at `Command-8`. Product review first reduced permanent ownership to
the five primary destinations and assigned refresh to `Command-R`, then removed
dynamic numbering entirely in favor of spatial arrow-key navigation.

SwiftUI `keyboardShortcut` remained useful for presentation and ordinary
buttons, but runtime verification showed that it did not reliably mutate the
sidebar `List(selection:)`. Fixed navigation therefore gained direct coordinator
dispatch.

## Open questions

- The available automation surface could not synthesize a physical one-second
  modifier hold, so reveal timing needs one manual keyboard pass.
- Trackpad swipe-back requires one manual gesture pass on physical hardware.
- User-configurable mappings remain intentionally deferred.
