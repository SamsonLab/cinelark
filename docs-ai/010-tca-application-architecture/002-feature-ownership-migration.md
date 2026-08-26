# 010.002 — Feature Ownership Migration

## Context

The root/navigation slice established TCA wiring, but legacy observable models
still owned library, detail, favorites, and playback state. This continuation
moves those responsibilities without keeping permanent compatibility
ownership.

## Change

- Add Profile, Search, Detail, Playback, and Remote reducers to `AppFeature`.
- Wrap persistence, playback, and gateway actors in dependency clients.
- Give replaceable requests and subscriptions feature-scoped cancellation IDs.
- Route view lifecycle and keyboard/remote intents through actions.
- Move UI-facing library data to Catalog projections, then remove overlapping
  state from observable models.

## Validation

- `TestStore` covers profile/source switching, search latest-wins, detail
  loading, playback lifecycle, and remote subscription termination.
- `TestClock` covers debounce, progress cadence, retry, and timeout behavior.
- The full macOS test target and package test suite remain green.

## Current state

Implemented and verified on 2026-08-26.

- `AppFeature` scopes Profile, Source, Library, Search, Navigation, Playback,
  and Remote. Media and person destination reducers are owned by `StackState`.
- Dependency clients wrap the Profile repository, media platform, IINA engine,
  and Remote gateway coordinator. Their runtime objects do not enter feature
  state.
- Search debounce and mirror retry use `TestClock`; library/search query
  effects are feature-cancellable and response actions carry query identity.
- Repository external changes and Remote snapshots enter reducers as internal
  actions through bounded `AsyncStream` subscriptions.
- Legacy UI-facing observable models and their duplicate views were removed in
  the same milestone. A repository search finds no `CachedMediaLibraryProvider`,
  `MediaLibraryProvider`, `AppModel`, or `PlaybackCoordinator` reference under
  `apps/macos/Sources` or `apps/macos/Tests`.
- Unsigned app build and the complete macOS test target pass. The remaining
  `RemoteCoordinator` is a transport/application-service boundary; TCA owns the
  rendered projection and product orchestration.
