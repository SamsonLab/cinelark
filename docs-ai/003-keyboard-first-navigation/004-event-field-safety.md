# 003.004 — NSEvent Field Safety

## Context

The shared local event monitor began observing pointer movement as part of
last-input-wins modality switching. Its callback extracted `keyCode`,
`charactersIgnoringModifiers`, and pointer deltas before dispatching by event
type. AppKit asserts when keyboard-only properties such as `keyCode` are read
from a mouse event, so every trackpad or mouse movement interrupted normal
pointer delivery and prevented hover control.

The input invariant is that an `NSEvent` property may only be read inside the
branch for an event family that defines that property.

## Change

- Pass the original `NSEvent` into the coordinator handler without eagerly
  extracting type-specific fields.
- Read modifier flags and key data only for flags-changed or key-down events.
- Read horizontal and vertical deltas only for swipe events.
- Keep pointer movement, button, drag, and scroll events free of keyboard-field
  access and return them to AppKit unconsumed.

## Validation

- Build the macOS application.
- Run package tests and `git diff --check`.
- Move the pointer with a trackpad or mouse and verify no AppKit assertion is
  emitted, hover takes ownership, and the event remains available to SwiftUI.
- Use an arrow key afterward and verify keyboard selection takes ownership
  again.

## Current state

Implemented in the current working tree. The local monitor passes the original
event into a type-dispatched handler. Pointer events no longer access
keyboard-only properties and remain unconsumed; keyboard and swipe fields are
read only inside their valid branches.

The macOS target builds successfully, all 36 package tests pass, and
`git diff --check` is clean. The latest Debug build launches and still accepts
directional navigation. The available UI automation drag action does not emit a
raw `MouseMoved` event, so final continuous-hover verification remains a manual
trackpad or mouse check.
