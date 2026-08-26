# 010 — TCA Application Architecture: Foundation Action

| | |
| --- | --- |
| **Status** | Implemented and verified |
| **Date** | 2026-08-26 |
| **Scope** | Root bootstrap, navigation, all application features, and catalog-backed UI ownership |

## Implemented

- Pinned `swift-composable-architecture` to exactly 1.26.1.
- Added `AppFeature`, `NavigationFeature`, `SourceFeature`, and the initial
  `LibraryFeature` boundary.
- Replaced heterogeneous SwiftUI navigation values with one `StackState` path
  for media, collection, and person routes.
- Moved the saved sidebar preference to `@Shared(.appStorage)` and separated it
  from the window-width-driven `NavigationSplitView` presentation state.
- Routed shortcuts through navigation actions instead of mutating a path or
  section binding directly.
- Preserved grid selection across column-count changes and re-anchored the
  selected item only when the column count changes.
- Added a `MediaPlatformClient` dependency boundary. Catalog records and plugin
  actors do not enter feature state.
- Added TCA-owned Profile, Search, Media Detail, Person Detail, Playback, and
  Remote features. View lifecycle and product commands enter through actions;
  transport and repository lifetimes remain dependency-owned.
- Restored persisted Profile/Source context only after source runtimes finish
  bootstrap, then projected that context into Library, Search, Playback, and
  Navigation.
- Added opaque-cursor pagination and latest-wins cancellation for library and
  search requests.
- Removed the legacy application, favorites, detail, playback, and playback
  options observable models together with their overlapping views. macOS UI no
  longer reads `CachedMediaLibraryProvider` or `MediaLibraryProvider`.

## Verification

- Unsigned `xcodebuild ... build` succeeds for the macOS application.
- `NavigationFeatureTests` verifies that detail round trips preserve the global
  sidebar preference and section changes clear the detail path.
- `LibraryFeatureTests` verifies that cached-first delivery is ordered and a
  slower cache read cannot overwrite the completed source refresh, and that
  pagination preserves opaque cursors while deduplicating catalog IDs.
- `SearchFeatureTests`, `PlaybackFeatureTests`, `ProfileFeatureTests`,
  `PersonDetailFeatureTests`, `RemoteFeatureTests`, and `AppFeatureTests` cover
  latest-wins search, playback lifecycle, profile import/mirror retry, person
  loading, remote projection, and two-phase bootstrap context restoration.
- The macOS test run passes 6 XCTest cases and 15 Swift Testing cases across 8
  suites.

## Operational caveat

CloudKit entitlements require a provisioning profile for
`com.samsonlab.cinelark`. Deterministic repository and reducer tests use
in-memory stores and pass without signing; a signed iCloud account smoke test
remains a release-environment check.
