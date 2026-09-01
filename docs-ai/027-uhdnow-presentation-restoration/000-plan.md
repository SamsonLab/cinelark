# 027 — UHDNow Presentation Restoration: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-28 |
| **Primary refs** | `LibraryFeature.swift`, `MediaDetailFeature.swift`, `CatalogLibraryViews.swift`, `CatalogMediaDetailView.swift`, `CatalogPersonDetailView.swift`, `SourceManagerView.swift` |
| **Related** | [TCA application architecture](../010-tca-application-architecture/000-plan.md), [Settings information architecture](../013-settings-information-architecture/000-plan.md), [Single personal Profile](../025-single-personal-profile/000-plan.md) |

## Background

The TCA and media-source migrations replaced the mature UHDNow presentation
layer with intentionally narrow catalog views. The new views retained the
correct ownership boundaries but lost important product behavior: the cinematic
home hierarchy, landscape resume shelf, per-library shelves, dense media detail
metadata, compact season and episode navigation, and the established keyboard
focus system.

The last presentation baseline before the TCA migration is `e9ec38f^`. Several
shared components from that baseline remain in the current tree, including
`PosterShelf`, `PosterGrid`, `CineLarkCinematicBackdrop`, filter controls, and
keyboard focus styles.

## Goals

- Restore the UHDNow visual hierarchy and interaction model for Home and media
  detail first.
- Restore Continue Watching, per-library Home shelves, and complete Series
  season/episode presentation from current TCA state.
- Restore the established Movies, Series, Favorites, and Person experiences.
- Align Settings, Profile, Sync, and Emby configuration surfaces with the same
  visual language without changing their ownership or data architecture.
- Preserve authenticated artwork, online Emby configuration, one personal
  iCloud Profile, local-first state, CloudKit sync, and TCA navigation.
- Preserve pointer, keyboard, shortcut, accessibility, loading, empty, and
  failure behavior.

### Non-goals

- Do not restore `AppModel`, `MediaLibraryProvider`, `PlaybackCoordinator`, the
  retired UHDNow private provider, or the legacy login flow.
- Do not replace `StackState` navigation with an independent `NavigationPath`.
- Do not introduce a second Profile, Source, playback, or catalog state owner.
- Do not change the media-source, Profile, CloudKit, or Emby contracts solely to
  reproduce presentation details.

## Design / Approach

### Presentation baseline

Use the view structure from `e9ec38f^` as the behavioral reference. Port view
bodies and local ephemeral UI state onto current TCA stores instead of restoring
the legacy observable models.

### State ownership

- `LibraryFeature` owns overview shelves, collection queries, local favorite
  projections, pagination, and source/profile context.
- `MediaDetailFeature` owns authoritative detail, seasons, episodes, local
  playback/favorite projections, and playback delegates.
- `PersonDetailFeature`, `ProfileFeature`, and `SourceFeature` remain the sole
  owners of their current domains.
- Views own only selection, expansion, pointer, focus, and scroll state.

### Navigation invariant

Sidebar rows remain selection-driven and TCA route destinations continue using
`NavigationLink(state:)`. The restored visual behavior must not reintroduce
value links that mutate the Store-backed navigation path at the same depth.

### Delivery order

1. Restore Home cinematic hierarchy, Continue Watching, Latest, and per-library
   shelves.
2. Restore media detail hero, metadata, playback state, season controls, episode
   rows, and people shelves.
3. Restore category filter bars, collection browser behavior, Favorites, and
   Person detail presentation.
4. Apply the shared hierarchy, spacing, materials, state messaging, and action
   styling to Settings, Profile/Sync, and Emby configuration.

### Verification

- Add reducer tests for keyed Home shelves, source/profile context changes,
  resume projection, season selection, and episode playback routing.
- Run the package and macOS test suites.
- Build the macOS app with the repository's normal signing-independent test
  path.
- Launch and inspect the main flows when the local signed runtime permits it.
- Record any runtime validation limitation precisely in `001-action.md`.

## Alternatives & decisions

- Reverting the TCA migration was rejected because it would restore duplicate
  state ownership and obsolete provider contracts.
- Recreating the legacy appearance with new parallel components was rejected
  because the current component library already contains most of the proven
  interaction system.
- Keeping the simplified catalog views and applying cosmetic changes was
  rejected because the regression is structural and state-driven, not merely
  visual.

## Amendments
