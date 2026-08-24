# 003.012 — Frosted Home Shelf Background

## Context

After the Home preview was fixed at its expanded geometry, the shelf viewport
continued to render over the shared near-black page canvas. The abrupt opaque
region visually separates shelf choices from the preview artwork even though
hover and keyboard selection update that artwork.

## Decision

Use the current preview artwork as a restrained, viewport-fixed shelf backdrop.
Place a native material layer and dark tint above it so the image supplies color
and continuity without competing with section titles, metadata, or focus rings.

## Change

- Add a Home-only shelf background using the same image URL as the preview.
- Cover the artwork with `ultraThinMaterial` to provide the frosted-glass effect.
- Add a translucent dark gradient for text and card contrast rather than an
  opaque black fill.
- Keep the background attached to the shelf viewport, not to individual shelf
  content, so vertical scrolling does not tile or move the effect.
- Preserve the existing Preview and shelf layout geometry.

## Validation

- `xcodebuild -project apps/macos/CineLark.xcodeproj -scheme CineLark
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build -quiet` completed
  successfully.
- `git diff --check` completed successfully.
- Static inspection confirmed that the background is attached outside the
  vertical ScrollView content, ignores hit testing, and leaves semantic scroll
  identifiers unchanged.
- Account-backed runtime contrast comparison was not run in this change.

## Current state

Implemented on 2026-08-24 in `apps/macos/Sources/Views/HomeView.swift`.

The shelf viewport displays the active preview artwork beneath native
`ultraThinMaterial`. A canvas-colored vertical gradient increases from 30%
opacity at the top to 56% at the bottom, preserving artwork color while
maintaining foreground contrast. The backdrop is scaled by 1.06 before clipping
so material blur does not expose hard image edges.

Updated 2026-08-24: This treatment was removed after runtime evaluation. The
current Home shelf background is the original opaque canvas — see
[003.014](014-restore-opaque-home-shelf-background.md).
