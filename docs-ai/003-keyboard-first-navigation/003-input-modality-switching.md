# 003.003 — Input Modality Switching

## Context

Semantic keyboard navigation preserves a stable selection while the pointer can
independently remain over another card. Presentation previously combined both
states with a boolean OR. After keyboard navigation began, a hovered card and a
keyboard-selected card could therefore render simultaneously, while stale
keyboard state could also prevent hover feedback from becoming authoritative.

The product invariant is last-input-wins: only the most recently used control
mode may present selection. Pointer movement or pointer activation enables hover
presentation and temporarily hides semantic keyboard selection. A handled
keyboard command restores semantic keyboard presentation and suppresses stale
hover state. The underlying semantic selection remains available so keyboard
navigation can resume from its previous position.

## Change

- Add a shared `pointer` / `keyboard` input modality to
  `ShortcutCoordinator`.
- Detect pointer movement, clicks, drags, and scrolling in the existing local
  event monitor without consuming those events.
- Switch to keyboard modality only when a relevant keyboard command is handled.
- Gate semantic outlines and activation badges on keyboard modality.
- Gate hover presentation on pointer modality across posters, playback cards,
  episodes, and people.
- Re-emit hover-driven preview highlighting when pointer modality is restored
  while the pointer remains inside the same card.

## Validation

- Build the macOS application.
- Select content with arrow keys, then move the pointer over a different card;
  verify only the hovered card remains selected.
- Press an arrow key while the pointer remains over that card; verify only the
  semantic keyboard target remains selected.
- Repeat on Home, detail episodes, and playback-version cards.
- Verify Return and Space continue to activate the semantic target after
  keyboard modality is restored.

## Current state

Implemented in the current working tree. `ShortcutCoordinator` owns the active
input modality, while views retain semantic keyboard selection independently
from its presentation. Pointer mode renders only hover state; keyboard mode
renders only semantic selection and its confirmation hint.

Hover transitions caused by layout or scrolling do not themselves establish
pointer intent. Only monitored physical pointer events may switch modality; see
[006-pointer-intent-boundary.md](006-pointer-intent-boundary.md).

The macOS target builds successfully, all 36 package tests pass, and
`git diff --check` is clean. Runtime verification confirmed that Home starts
without a semantic confirmation badge and that directional input restores one
keyboard outline and one confirmation badge. The available UI automation layer
does not synthesize a raw mouse-move event over an arbitrary point, so the final
pointer-hover takeover still requires a manual cursor pass.
