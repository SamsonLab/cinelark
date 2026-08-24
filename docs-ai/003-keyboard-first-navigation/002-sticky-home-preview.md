# Sticky Home Preview and Section Anchoring

## Context

Home originally placed the preview and every shelf in one vertical scroll view.
Continue Watching overlapped the preview with negative top padding, while the
keyboard route scrolled to the shelf's outer container. That combination made
the cards, rather than the `Continue Watching` heading, appear at the top. It
also allowed the preview to leave the viewport entirely.

The desired behavior is closer to Apple TV: the current preview remains visible
as browsing moves through shelves, contracts as vertical scrolling progresses,
and expands again at the top. Section navigation must align a shelf's semantic
heading without relying on a visual offset.

## Change

- Separate the persistent preview from the shelves' vertical scroll container.
- Derive a bounded collapse progress from the shelves' scroll geometry and use
  it to resize the preview without adding an animation transaction per frame.
- Preserve the visual overlap through container layout rather than applying
  negative padding to Continue Watching, then reduce that overlap to zero as
  the preview contracts.
- Give Continue Watching a dedicated heading anchor and route keyboard section
  movement to that anchor.
- Route Hero selection to the scroll content's top anchor so the preview expands
  deterministically.
- Keep preview highlighting active while the compact preview is visible.
- Extend the preview into the detail column's top safe area and use smaller
  adaptive height bounds for shorter windows.
- Re-align a programmatic keyboard scroll after the preview's 200 ms layout
  transition so the selected shelf cannot drift below the viewport.

## Validation

- Build the macOS application.
- Verify pointer and trackpad scrolling keep the preview visible and smoothly
  contract it to the configured compact height.
- Verify scrolling back to the top restores the expanded preview.
- Verify moving from Hero to Continue Watching places the heading, not only its
  cards, at the top of the content viewport.
- Verify Return and Space still activate the selected Continue Watching item.

## Current state

Implemented in the current working tree. The expanded preview remains visible at
the top of Home and contracts to a 260–360 point compact range. Its metadata and
actions scale and shift upward, while the shelf overlap fades from 118 points to
zero. Continue Watching and every subsequent shelf align by semantic heading.

The macOS application builds successfully. Runtime checks in a 960 × 690 window
confirmed that the backdrop reaches the top edge, compact controls do not
collide with shelf headings, Continue Watching retains its heading when selected,
and a deeper collection aligns its heading and selected poster below the sticky
preview.

Updated 2026-08-24 by
[003.011](011-static-home-preview-geometry.md): the persistent preview and
semantic heading anchors remain current, but scroll-responsive resizing,
content transforms, and overlap reduction are no longer part of the Home
layout. The preview now retains the former expanded-state geometry.
