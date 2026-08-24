# 003.015 — Visible Series Detail Navigation

## Context

Series detail keeps semantic keyboard selection independently from scroll
position. That selection can become stale after manual scrolling, and the
episode expansion control changes position from immediately after episode 6 to
the bottom of the complete season. If `showMore` remains selected during that
change, the next Up command treats the relocated control as its origin and
jumps to the final episode rather than moving relative to the visible rows.

Episode rows are also their own top-aligned scroll targets. Aligning a focused
row exactly to the viewport edge can clip the focus scale and outline.

## Change

- Track visibility for detail sections and individual episode-list targets.
- Accept a remembered or pointer target as an arrow origin only while that
  target is visible.
- When the origin is stale, derive a direction-aware boundary target from the
  currently visible rows before applying exactly one normal navigation step.
- When expanding the list from the keyboard, move focus from the expansion
  control to the first newly revealed episode. When collapsing, move focus to
  the last retained episode.
- Include focus clearance in episode scroll targets so top alignment leaves
  room for the selected row's focus treatment.

## Validation

- `xcodebuild -project apps/macos/CineLark.xcodeproj -scheme CineLark
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build -quiet` completed
  successfully.
- Local runtime validation used the 33-episode season of `重器`. Keyboard
  expansion moved focus from the expansion control to episode 7, whose focus
  outline remained fully visible below the viewport edge.
- After manual scrolling, Up rebased from the visible episode boundary and
  changed the vertical offset from approximately 42% to 28% instead of jumping
  to the old expansion-control position.
- A second manual scroll followed by Down changed the offset from approximately
  36% to 46%, selecting the next visible-boundary episode without jumping to the
  end or emptying the lazy list.
- `git diff --check` completed successfully.

## Current state

Implemented on 2026-08-24 in `MediaDetailView`.

The root detail scroll view consumes the episode LazyVStack's native visible
scroll-target IDs at a 15% threshold. Section-level visibility remains separate
for Hero, Seasons, movie versions, and Cast. Arrow navigation accepts a target
as its origin only when the relevant visibility source contains it; otherwise
Up and Down use the first or last visible semantic target before applying one
normal move.

Episode targets contain 18 points of top focus clearance. Keyboard expansion
moves selection to episode 7 after the expanded rows mount, while collapse
moves selection to episode 6. Both pointer and keyboard expansion clear the old
expansion-control visibility before its layout position changes.
