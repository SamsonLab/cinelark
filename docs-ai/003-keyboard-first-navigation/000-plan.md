# 003 — Keyboard-First Application Navigation: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-24 |
| **Primary refs** | Implementation commit containing this record |
| **Related** | [002 — Keyboard shortcut system](../002-keyboard-shortcut-system/000-plan.md) |

## Background

The first keyboard-shortcut implementation established fixed sidebar commands,
directional poster-grid selection, overlay help, and shared back semantics. Its
directional route is a single replaceable callback, however, so a temporary
surface can erase its parent route. Home and detail pages also rely mostly on
implicit SwiftUI focus traversal and therefore cannot guarantee an initial
selection, spatial movement, visibility, or activation behavior.

The local AppKit event monitor is started and stopped with `RootView` appearance.
Window or application lifecycle transitions can consequently leave the monitor
missing or retain stale modifier state. Shortcut help is attached inside the
library split view rather than at the window root, which also prevents it from
being a true application-wide overlay.

## Goals

- Make the application's core browse, detail, playback, and navigation paths
  operable with arrow keys, Return or Space, Escape or Backspace, and the fixed
  Command shortcuts.
- Give each page a deterministic, model-backed focus graph instead of deriving
  navigation from transient view geometry.
- Keep the selected target visible, preferring top or leading alignment when a
  selection moves into a newly visible section.
- Preserve a parent navigation surface while a sheet or child surface is active.
- Keep the local event monitor and Command-hold state correct across application
  activation, window replacement, and root-view reconstruction.
- Render shortcut and directional help above the entire application without
  changing layout or scroll geometry.
- Retain native text-editing behavior and avoid intercepting key events owned by
  editable controls.

### Non-goals

- Replacing AppKit's local event monitor with system-wide global hotkeys.
- Assigning numeric shortcuts to dynamic content.
- Persisting a content selection across application launches.
- Building a geometry-driven spatial search engine for arbitrary controls.
- Making every secondary metadata label focusable.

## Design / Approach

### Navigation surface stack

`ShortcutCoordinator` will replace its single directional callback with an
ordered stack of registered navigation surfaces. A surface supplies movement and
activation closures and is identified by a stable owner token. The most recently
registered visible surface receives arrow, Return, and Space events. Removing a
sheet's surface automatically restores its parent page without requiring the
parent to reappear.

Surfaces own only semantic state. Pages build focus graphs from current model
collections and represent targets by stable identifiers. Horizontal movement
changes the target inside a section. Vertical movement restores the adjacent
section's own last valid target, using index zero only as its initial or invalid-
state fallback. Collection updates reconcile active and remembered selections.

Reusable cards receive selection as presentation state. Their scroll containers
use `ScrollViewReader` to reveal the selected identifier with top or leading
alignment. The shared focus-surface treatment provides a visible outline and a
small keyboard-action label when helpful.

### Page coverage

- Home owns a graph spanning hero actions, Continue Watching, and media shelves.
  Return or Space performs the selected target's primary action.
- Movie and series detail pages own hero actions, movie versions, seasons,
  episodes, expansion controls, and cast navigation.
- Playback option sheets temporarily override the detail route and restore it on
  dismissal.
- Poster grids continue to use column-aware movement and top-aligned scrolling.
  Person and favorites surfaces adopt the same selection contract where their
  content is dynamic.
- Fixed sidebar destinations remain `Command-1` through `Command-5`; refresh
  remains `Command-R`, and Search input recovery uses `Command-F`.

### Event and overlay lifecycle

`ShortcutCoordinator.start()` remains idempotent and installs both the local
event monitor and application activation observers. Resigning active cancels the
hold task, hides help, and clears modifier state. Becoming active ensures the
monitor exists and starts from a clean state. Root-view disappearance no longer
owns coordinator shutdown.

The shared shortcut legend moves to the window root. Per-control badges remain
local overlays, but global arrow, activation, and back guidance is presented at
the root so it remains visible over every application phase and navigation page.

### Event priority

Editable controls and modal controls retain first priority. When text input or a
system modal owns the event, the coordinator passes it through. Otherwise the
active surface receives arrows and Return or Space. Escape and Backspace use the
existing contextual back path, with sheets dismissed before navigation stacks
are popped.

## Alternatives & decisions

| Alternative | Decision |
| --- | --- |
| Rely only on implicit SwiftUI focus traversal | Rejected because Home did not establish a reliable first target and selected content could move outside the visible region. |
| Keep one replaceable directional callback | Rejected because sheets and nested surfaces erase the parent route on dismissal. |
| Register every visible card independently | Rejected because registration order is not a semantic focus graph and changes with lazy rendering. |
| Calculate nearest controls from view geometry | Rejected because it couples navigation behavior to transient layout and scrolling details. |
| Start and stop monitoring with `RootView` | Rejected because view lifecycle is not application input lifecycle. |

## Validation

- Build the macOS application with warnings treated as errors where practical.
- Verify Home can establish a selection, move across and between shelves, keep
  the selected target visible, and activate it with Return and Space.
- Verify movie and series details cover hero actions and dynamic sections with
  arrows and activation keys.
- Verify a playback sheet overrides detail navigation and that dismissing it
  restores the detail selection.
- Verify Escape and Backspace dismiss or navigate back consistently outside text
  editing, while Search and other editable controls keep native key behavior.
- Verify Command help appears after one second, is a root overlay, and still
  works after application deactivation and reactivation.

Updated 2026-08-24: The Home preview is now treated as a persistent,
scroll-responsive region, and Continue Watching navigation aligns to its
heading instead of the card body — see
[002-sticky-home-preview.md](002-sticky-home-preview.md).

- Updated 2026-08-24: Semantic keyboard selection and pointer hover now share
  an explicit last-input-wins modality — see
  [003-input-modality-switching.md](003-input-modality-switching.md).

- Updated 2026-08-24: Event-specific properties must only be read inside their
  valid AppKit event-family branch — see
  [004-event-field-safety.md](004-event-field-safety.md).

- Updated 2026-08-24: Pointer and keyboard selections remain independent but
  transfer their active target during control-mode handoff — see
  [005-selection-handoff.md](005-selection-handoff.md).

- Updated 2026-08-24: Hover transitions no longer imply pointer intent; only
  physical pointer events may switch the active input modality — see
  [006-pointer-intent-boundary.md](006-pointer-intent-boundary.md).

- Updated 2026-08-24: Vertical transitions briefly used a fixed index-zero
  origin instead of preserving the source column; this was later superseded by
  section-local memory — see
  [007-section-entry-origin.md](007-section-entry-origin.md).

- Updated 2026-08-24: Search, empty Favorites tabs, focus-scale clearance, and
  narrow filter viewports now retain complete keyboard behavior — see
  [008-navigation-boundary-completeness.md](008-navigation-boundary-completeness.md).

- Updated 2026-08-24: Cross-section navigation restores each destination's own
  last valid target instead of forcing every entry to index zero — see
  [009-section-selection-memory.md](009-section-selection-memory.md).

- Updated 2026-08-24: Poster scrolling targets include focus-scale clearance so
  top alignment cannot clip selected artwork — see
  [010-focus-safe-scroll-targets.md](010-focus-safe-scroll-targets.md).

- Updated 2026-08-24: The Home preview now retains its original expanded
  geometry instead of resizing and transforming with shelf scroll position;
  this supersedes the scroll-responsive geometry described in 003.002 while
  preserving its persistent-preview and semantic-anchor decisions — see
  [011-static-home-preview-geometry.md](011-static-home-preview-geometry.md).

- Updated 2026-08-24: Home shelves now use the current preview artwork beneath a
  dark native-material treatment instead of an opaque near-black field — see
  [012-frosted-home-shelf-background.md](012-frosted-home-shelf-background.md).

- Updated 2026-08-24: Home arrow navigation now rebases stale offscreen
  selection on the visible shelf boundary, and horizontal shelf targets include
  leading focus clearance — see
  [013-visible-home-navigation-origin.md](013-visible-home-navigation-origin.md).

- Updated 2026-08-24: The experimental frosted Home shelf treatment was removed
  and the opaque canvas restored — see
  [014-restore-opaque-home-shelf-background.md](014-restore-opaque-home-shelf-background.md).

- Updated 2026-08-24: Series detail navigation now rejects stale offscreen
  episode origins and moves focus deterministically when the episode list is
  expanded or collapsed — see
  [015-visible-series-detail-navigation.md](015-visible-series-detail-navigation.md).

- Updated 2026-08-26: Sidebar visibility becomes root-owned semantic state and
  collection grids restore a stable selected anchor across navigation and
  geometry changes — see
  [016-global-sidebar-and-grid-restoration.md](016-global-sidebar-and-grid-restoration.md).
