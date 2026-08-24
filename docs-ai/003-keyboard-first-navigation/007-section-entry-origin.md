# 003.007 — Section Entry Origin

## Context

Directional navigation previously preserved the source item's column when Up or
Down crossed between semantic sections. That behavior is spatially plausible,
but makes the destination depend on navigation history and can land deep inside
a shelf or control group.

For CineLark's ordered content sections, vertical movement expresses section
navigation rather than nearest-neighbor navigation. Entering a section should
therefore have a stable origin.

## Change

- Keep Left and Right movement local to the current section.
- Make every Up or Down transition between sections select target index zero in
  the destination section.
- Apply the same rule to Home shelves, detail sections, and transitions between
  grid content and leading filter or favorite controls.
- Continue scrolling the destination section or item to its existing top or
  leading alignment.

## Validation

- Move to a nonzero item in a Home shelf, then press Up or Down; verify the first
  target in the destination section is selected.
- Repeat between detail sections with different axes and lengths.
- From a nonzero first-row poster, press Up into leading actions; verify the
  first leading action is selected.
- Build the macOS application, run package tests, and run `git diff --check`.

## Current state

Superseded in the current working tree by
[009-section-selection-memory.md](009-section-selection-memory.md).

The fixed-origin behavior briefly existed in the working tree, but runtime and
interaction review showed that it discarded useful local context.

Home, detail, poster-grid, and Favorites transitions now restore the destination
section's own last valid target. Index zero remains only the fallback for an
unvisited section or invalidated model identifier.
