# 003.005 — Selection Handoff

## Context

Last-input-wins modality switching made pointer hover and keyboard selection
visually exclusive, but each mode retained an unrelated target. After hovering
one card, the next arrow or confirmation key could therefore resume from an old
keyboard target instead of the content currently under the pointer.

Pointer and keyboard selections must remain independent state because pointer
hit testing and semantic keyboard graphs have different lifecycles. They must
also support an explicit handoff so a control-mode change preserves the user's
current spatial context.

## Change

- Let each page or reusable navigation container retain a typed pointer target
  separately from its keyboard target.
- Extend registered navigation surfaces with a `handoffToKeyboard` callback.
- Before a directional or confirmation command is dispatched from pointer mode,
  copy the current pointer target into the semantic keyboard selection.
- Apply the requested direction after handoff, so an arrow advances relative to
  the hovered target. Return or Space activates the handed-off target.
- Update pointer targets on hover entry, clear them on matching hover exit, and
  refresh them when pointer modality resumes while the cursor remains inside a
  control.
- Keep presentation last-input-wins: handoff transfers semantic context, not a
  second visible outline.

## Validation

- Hover a Home shelf item, press Left or Right, and verify navigation advances
  relative to that item.
- Hover a target and press Return or Space; verify that exact target activates.
- Repeat across poster grids, detail episodes and cast, playback-version cards,
  and filter or favorite leading actions.
- Switch repeatedly between pointer and keyboard and verify only the active
  modality renders selection.
- Build the macOS application, run package tests, and run `git diff --check`.

## Current state

Implemented in the current working tree.

Each covered surface now retains a typed pointer target beside its semantic
keyboard target. `ShortcutCoordinator` asks the active surface to hand that
target to keyboard state before dispatching a directional or confirmation
event. Movement and activation also read the current pointer target directly
while the event is still in pointer mode; this avoids losing the first command
to SwiftUI state-transaction latency. The handled event then changes the active
presentation modality, so only the resulting keyboard target is visible.

The same contract is applied to Home shelves and hero actions, poster grids and
their leading controls, detail actions and dynamic rows, favorite people, and
playback-version cards. Pointer re-entry restores the real control under the
cursor without destroying the retained keyboard position.
