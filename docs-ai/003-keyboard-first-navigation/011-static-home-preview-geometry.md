# 003.011 — Static Home Preview Geometry

## Context

The sticky Home preview introduced in 003.002 derives its height, content scale,
content offset, bottom padding, and shelf overlap from the vertical shelf scroll
offset. Although the expanded state has the intended composition, scrolling
changes that composition and produces different visible shelf clearances for
Continue Watching and poster shelves.

An interim implementation removed the scale transition but sized the preview by
subtracting an estimated first-shelf height from the viewport. That makes the
preview geometry depend on whether Continue Watching is present and gives the
first shelf a layout contract that later shelves cannot share.

## Decision

Keep the original expanded preview composition as the invariant Home layout.
Scrolling the shelves must not resize or transform the preview. Shelf content
remains independently scrollable beneath the preview, and semantic heading
anchors remain unchanged.

## Change

- Remove vertical scroll-offset observation from Home.
- Use the former expanded preview height at every scroll position: 82% of the
  viewport, clamped to 440–690 points.
- Keep the expanded content bottom padding: 170 points when Continue Watching
  overlaps the preview and 64 points otherwise.
- Keep the 118-point overlap whenever Continue Watching is present.
- Remove scroll-driven content scale and vertical offset transforms.
- Do not estimate the preview height from the type or height of the first shelf.

## Validation

- `xcodebuild -project apps/macos/CineLark.xcodeproj -scheme CineLark
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build -quiet` completed
  successfully.
- `git diff --check` completed successfully.
- Static inspection confirmed that scroll offset is no longer observed, preview
  transforms are absent, both Continue Watching states share the same height
  rule, and keyboard section identifiers and scroll targets are unchanged.
- Account-backed runtime comparison at multiple scroll positions was not run in
  this change.

## Current state

Implemented on 2026-08-24 in `apps/macos/Sources/Views/HomeView.swift`.

The Home preview now remains at its former expanded height at every shelf scroll
position. Its content uses the expanded-state bottom padding without scale or
offset transforms. Continue Watching retains the existing 118-point overlap,
and the absence of Continue Watching changes only that overlap and content
padding, not the preview height rule.

The stale current-state description in
`002-sticky-home-preview.md` was amended to distinguish the persistent-preview
and semantic-anchor behavior that remains current from the scroll-responsive
geometry superseded here.
