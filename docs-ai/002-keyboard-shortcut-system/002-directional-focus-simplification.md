# 002 — Directional Focus Simplification

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-21 |
| **Primary refs** | Implementation commit containing this record |
| **Amends** | [Keyboard shortcut system plan](000-plan.md) |

## Trigger

The dynamic shortcut allocator made Command help slower and required visible
controls to register identity, geometry, enabled state, and lifecycle. That
machinery was disproportionate for media content whose spatial arrangement is
already understandable with arrow keys.

## Decision

- Command help reveals after a one-second hold.
- Only `Command-1...5` and `Command-R` retain fixed shortcuts.
- Dynamic numeric assignment and its geometry registry are removed.
- Arrow keys select dynamic media spatially; the selected card receives an
  explicit focus outline and Return or Space opens it.
- A literal arrow-key and Return/Space legend appears in a glass overlay above
  the complete split view while Command help is visible.
- Fixed badges remain overlays attached to their controls. No help surface may
  affect layout measurement or scroll position.

## Implementation notes

`ShortcutCoordinator` now holds one active directional route rather than a list
of visible targets. `PosterGrid` derives vertical movement from its current
column count and retains the selected model ID independently of SwiftUI's focus
engine so the outline is deterministic. Activation is routed through the
library `NavigationPath`.

Text editing retains priority. Search removes field focus after Return submits,
allowing subsequent arrow input to enter result navigation. The AppKit responder
guard checks `isEditable` instead of blocking every `NSTextView` or
`NSTextField`, because non-editing responders otherwise suppressed Return on
media grids.

## Verification

- Debug `xcodebuild` succeeded on macOS.
- Running-app verification selected Movies with `Command-2`.
- The first poster rendered the shared focus outline; Right moved the outline to
  the second poster.
- Return and Space each opened the selected poster's media detail view.
- Physical modifier-hold timing and trackpad swipe-back remain manual checks.
