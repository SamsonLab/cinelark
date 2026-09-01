# 003.017 — Detail Route Surface Ownership

## Context

The published 0.1.10 application accepts directional input after a media detail
route is pushed, but the current working-tree application is reported to stop
responding after the same transition. The detail view already defines a semantic
focus graph, so the regression is expected at the navigation-surface ownership
boundary rather than in individual arrow mappings.

The highest-probability failure modes are:

1. the detail surface is not the coordinator's active surface after the route
   transition or a later parent update;
2. the detail surface is removed or replaced during SwiftUI reconstruction;
3. the event is rejected because modal or first-responder state is classified
   incorrectly.

## Change

- Added explicit `page`, `route`, and `modal` levels to registered navigation
  surfaces. Active-surface resolution compares level before registration order.
- Classified media, collection, and person detail surfaces as `route`; playback
  options are `modal`; top-level browse and search surfaces remain `page`.
- Kept registration order as the tie-breaker within one level, preserving sibling
  replacement and parent restoration behavior.
- Added coordinator regression tests proving that a late page registration cannot
  steal route input, removing a route restores the page surface, and a modal
  surface outranks a route even when that route registers later.

## Validation

- The first focused coordinator test was run before implementation and failed to
  compile because the level contract did not exist; all three coordinator tests
  passed after implementation.
- `xcodebuild -quiet -project apps/macos/CineLark.xcodeproj -scheme CineLark
  -configuration Debug -derivedDataPath build/DerivedData -destination
  'platform=macOS' CODE_SIGNING_ALLOWED=NO test` passed all 63 tests.
- The corresponding unsigned Debug build completed successfully.
- `git diff --check` reported no whitespace errors.
- The installed 0.1.10 application was exercised separately: media detail accepted
  horizontal and vertical input, including scrolling from hero actions to seasons
  and episodes. It does not contain this working-tree fix.
- End-to-end UI validation of the working-tree binary remains pending because the
  local machine has no matching development provisioning profile. An attempted
  ad-hoc launch correctly failed in Core Data CloudKit setup because ad-hoc signing
  cannot authorize the configured iCloud container; that crash is unrelated to
  navigation dispatch.

## Current state

Implemented on 2026-09-01.

Navigation-surface ownership is now semantic rather than purely temporal. A
hidden page may register or refresh its surface while a pushed route is visible,
but it cannot receive direction, activation, or pointer-to-keyboard handoff until
all route-level surfaces are removed. A presented playback surface overrides its
route and automatically reveals that route again on dismissal.
