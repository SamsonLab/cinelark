# 003.014 — Restore Opaque Home Shelf Background

## Context

003.012 placed the active Preview artwork beneath native material and a dark
gradient in the Home shelf viewport. Runtime use showed that the resulting
frosted treatment reduced the intended visual separation and clarity.

## Change

- Remove the Home-only shelf artwork and material background.
- Let the shelf viewport render over the existing opaque
  `CineLarkPageBackground` canvas again.
- Preserve static Preview geometry, shelf layout, and visible-section keyboard
  navigation without modification.

## Validation

- `xcodebuild -project apps/macos/CineLark.xcodeproj -scheme CineLark
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build -quiet` completed
  successfully.
- `git diff --check` completed successfully.
- Static inspection confirmed that no Home shelf material or duplicated Preview
  artwork remains.

## Current state

Implemented on 2026-08-24 in `apps/macos/Sources/Views/HomeView.swift`.

The shelf viewport is transparent to the existing opaque page canvas. Static
Preview geometry and visible-section keyboard navigation remain unchanged.
