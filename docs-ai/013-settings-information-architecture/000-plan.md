# 013 — Settings Information Architecture: Plan

| | |
| --- | --- |
| **Status** | Implemented and verified |
| **Anchor date** | 2026-08-26 |
| **Primary refs** | `CineLarkSettingsView`, `RootView`, `LibraryView` |
| **Related** | [`../010-tca-application-architecture/000-plan.md`](../010-tca-application-architecture/000-plan.md), [`../011-media-source-platform/000-plan.md`](../011-media-source-platform/000-plan.md), [`../012-cache-management/000-plan.md`](../012-cache-management/000-plan.md) |

## Background

CineLark now owns Profiles, media Sources, Remote pairing, cache management,
language selection, and update behavior. Exposing each capability as a toolbar
button, sheet, or sidebar utility makes the browsing shell reflect the number
of configuration features instead of the user's content hierarchy.

macOS already provides a persistent Settings scene and conventional Command-,
entry point. Configuration should converge there while the main sidebar remains
stable as product capabilities grow.

## Goals

- Keep the library sidebar limited to content destinations.
- Keep refresh as a contextual library toolbar command rather than a setting.
- Replace separate Sources and Remote toolbar buttons/sheets with one Settings
  entry point.
- Provide native Settings categories for General, Profiles & Sources, Remote,
  and Storage.
- Move language, version, and update controls into General.
- Reuse existing TCA stores and dependency lifetimes; Settings views do not
  introduce duplicate observable ownership.
- Preserve source setup cancellation and Remote pairing start/termination when
  users switch Settings categories or close the window.

### Non-goals

- Redesigning the individual Emby/UHDNow setup protocol.
- Moving content destinations such as Search or Favorites into Settings.
- Adding a custom preferences persistence framework.
- Replacing macOS Settings with an application-specific navigation window.

## Design / Approach

1. Add one `CineLarkSettingsView` composition view backed by the root Store.
2. Use a native macOS settings `TabView` with four stable categories:
   General, Profiles & Sources, Remote, and Storage.
3. Refactor current sheet-only settings views into embeddable category content.
   Category disappearance ends transient setup/pairing work.
4. Remove `showsSourceManager` from `AppFeature`; presentation belongs to the
   system Settings scene, not application business state.
5. Remove Sources, Remote, language, and version controls from the browsing
   shell. Keep a single `SettingsLink` for discoverability and the normal app
   menu Settings command.
6. Move Refresh to the library toolbar and preserve Command-R behavior.
7. Verify reducer ownership, application compilation, and all macOS tests.

## Alternatives & decisions

- **Rejected: keep one toolbar button per subsystem.** Toolbar complexity would
  continue growing with downloads, subtitles, accounts, and new source types.
- **Rejected: put configuration rows at the bottom of the sidebar.** They are
  not content destinations and make sidebar layout depend on enabled features.
- **Rejected: retain sheet presentation state in `AppFeature`.** The Settings
  scene already owns window presentation; mirroring it in TCA creates a second
  authority without business value.
- **Decision: retain one visible Settings affordance.** The macOS app menu is
  canonical, while a single gear button keeps source setup discoverable for
  users who do not know Command-,.

## Amendments
