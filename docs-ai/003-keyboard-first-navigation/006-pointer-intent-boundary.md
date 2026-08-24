# 003.006 — Pointer Intent Boundary

## Context

SwiftUI can emit `onHover` transitions without physical pointer movement when
keyboard navigation scrolls or re-lays out content beneath a stationary cursor.
Treating every hover entry as pointer intent lets that stationary cursor steal
selection immediately after a keyboard command.

Hover state describes hit testing, not necessarily the user's latest input.
Input modality must be driven by raw input events, while hover state only
identifies the target to use after pointer intent has been established.

## Change

- Let the AppKit event monitor remain the sole source of pointer-modality
  activation through mouse movement, clicks, drags, and scroll-wheel events.
- Remove pointer-modality activation from SwiftUI `onHover` callbacks.
- Continue tracking local hover geometry, but publish hover entry as a retained
  pointer target only after pointer intent is active. Hover exit may still clear
  a stale target.
- Keep hover presentation gated by pointer modality, preventing geometry-driven
  hover changes from interrupting keyboard selection.

## Validation

- Park the pointer over a selectable region, then navigate and scroll with arrow
  keys; keyboard selection must remain active as content moves beneath it.
- Move the pointer afterward; the newly hovered target must take over in the
  same pointer interaction.
- Verify clicks, drags, and scroll-wheel input still switch to pointer mode.
- Build the macOS application, run package tests, and run `git diff --check`.

## Current state

Implemented in the current working tree.

`ShortcutCoordinator` now activates pointer modality only from its monitored
AppKit pointer-event families. Its activation method is private, preventing view
hover handlers from becoming a second modality source.

Hover handlers still retain local hit-test state. Hover exit may clear a stale
pointer target in either modality, while hover entry writes a target or preview
only when pointer modality is already active. When a genuine pointer event
restores that modality, controls already under the pointer re-emit their target
through the modality observer.
