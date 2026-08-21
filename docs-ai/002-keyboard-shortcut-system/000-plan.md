# 002 — Keyboard Shortcut System: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-21 |
| **Primary refs** | Implementation commit containing this record |
| **Related** | [001 — AI knowledge system](../001-ai-knowledge-system/000-plan.md) |

## Background

CineLark's TV-first interface contains many context-dependent controls. Numbering
that dynamic content would become stale as filters, search results, expanded
sections, and scroll position change. Permanent top-level navigation still
benefits from stable muscle memory, while content browsing is better represented
by spatial keyboard focus.

## Goals

- Reserve `Command-1` through `Command-5` for Home, Movies, TV Series,
  Favorites, and Search.
- Use the conventional `Command-R` shortcut for refresh.
- Reveal shortcut help after Command has been held for one second.
- Keep numeric shortcuts limited to the small, stable command set.
- Navigate dynamic content spatially with arrow keys, render an explicit focus
  outline, and activate the selected item with Return or Space.
- Present every shortcut reminder as an overlay so revealing help never changes
  layout or scroll geometry.
- Support Return-driven submission, Escape dismissal, Backspace navigation,
  command-based back navigation, and trackpad swipe-back where appropriate.

### Non-goals

- System-wide global hotkeys while CineLark is inactive.
- User-configurable shortcut mappings in this phase.
- Assigning numeric shortcuts to dynamic media, filters, language selection, or
  other state-dependent controls.

## Design / Approach

`ShortcutCoordinator` owns one local AppKit event monitor, the one-second hold
state, fixed command dispatch, directional selection, Return activation, and
navigation-back dispatch. The coordinator stores only the active content
surface's small movement and activation closures; it does not observe every
visible control or generate numeric assignments.

Dynamic media grids retain one selected model identity. Arrow keys update that
identity using the current grid column count, and the selected card reuses the
shared focus surface for a visible outline. Return and Space route the selected
media through the application's `NavigationPath`. Search keeps keyboard input
owned by its editable field until submission removes field focus.

Fixed badges use per-control SwiftUI overlays. The directional legend uses a
single bottom overlay above the whole split view. Neither participates in layout.

Fixed navigation is dispatched by the coordinator instead of relying solely on
SwiftUI `keyboardShortcut`, because sidebar `NavigationLink` shortcuts did not
reliably mutate `List(selection:)` during runtime verification. SwiftUI shortcut
modifiers remain responsible for badge presentation and ordinary button wiring.

The navigation stack exposes one back action to the coordinator. Backspace,
`Command-[`, `Command-Left`, Escape handling owned by the current view, and
horizontal trackpad swipe events all converge on native view or stack semantics
without affecting text editing or presented modal UI.

## Alternatives & decisions

| Alternative | Decision |
| --- | --- |
| Dynamically number visible controls | Rejected after implementation because assignment lifecycle and geometry tracking add complexity without improving spatial media browsing. |
| Permanently assign every control | Rejected because the action set is state-dependent and would exhaust memorable chords. |
| Use only SwiftUI `keyboardShortcut` | Rejected after fixed sidebar navigation failed runtime verification. |
| Show badges immediately on Command-down | Rejected because normal application shortcuts should not flash the help surface. |

## Amendments

- Updated 2026-08-21: Replaced dynamic numbering with directional focus and
  unified Return/Space confirmation — see
  [002 — Directional focus simplification](002-directional-focus-simplification.md).
