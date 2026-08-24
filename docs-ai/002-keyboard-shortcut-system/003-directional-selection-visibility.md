# 003 — Directional Selection Visibility

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-24 |
| **Primary refs** | Working tree on 2026-08-24; commit pending |
| **Amends** | [Keyboard shortcut system plan](000-plan.md) |

## Context

Directional selection updated the selected media identity without explicitly
coordinating the containing scroll view. SwiftUI focus movement could therefore
select a poster outside the visible viewport.

## Change

- Every directional move must reveal the selected poster.
- The poster's row should align to the viewport top when scroll bounds permit.
- Near the content end, scrolling should move as far toward top alignment as the
  remaining content allows.
- Selection, focus outline, and scrolling must update as one user action.
- The behavior must not restore per-item geometry observation.

## Validation

- Debug `xcodebuild` succeeded on macOS.
- In Movies, Down selected the first poster in the next row and aligned that row
  to the grid viewport top.
- Three additional Down presses in rapid succession kept the final selected row
  visible and top-aligned.
- The selected outline remained visible after each observed move.

## Current state

`PosterGrid` wraps its vertical scroll view in `ScrollViewReader`. Each poster
has an explicit model ID, and the shared selection transaction updates the
selected ID, SwiftUI focus binding, and `scrollTo(..., anchor: .top)` together.
No per-card geometry observation was introduced.
