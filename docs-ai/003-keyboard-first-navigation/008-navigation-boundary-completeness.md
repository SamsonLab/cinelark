# 003.008 — Navigation Boundary Completeness

## Context

Search, Favorites, and category filters expose navigation boundaries that are
not represented by poster content alone. Poster focus scaling also needs clear
space above the first row. Empty result sets can remove the only registered
navigation surface, completed searches need a deterministic way back to text
entry, and long filter rows can move semantic selection outside a narrow
viewport.

## Change

- Add a reusable first-row focus-safe inset and apply it to Search and Favorites
  poster content, including favorite people.
- Keep Favorites navigation surfaces alive when the selected tab is empty, so
  directional input can still select and activate its tabs.
- Register a Search-owned fallback navigation surface whenever result cards are
  absent, and add `Command-F` as the explicit command for returning focus to the
  search field after submission.
- Present the `Command-F` chord on the search field while shortcut help is
  visible.
- Make shared horizontal filter bars observe semantic keyboard selection and
  scroll the selected filter into view, centered where possible.

## Validation

- Verify focused Search and Favorites cards have enough top clearance at hover
  and keyboard focus scale.
- Select an empty Favorites tab and confirm arrows can still reach all tabs and
  Return or Space can activate them.
- Submit Search, navigate results, press `Command-F`, and verify text input
  immediately regains focus. Repeat with no results.
- Narrow the TV Series window and traverse every category with arrow keys;
  verify each selected filter scrolls into view.
- Build the macOS application, run package tests, and run `git diff --check`.

## Current state

Implemented in the current working tree.

Search now owns a fallback navigation surface and a `Command-F` action that
restores text focus after submission. Search and Favorites grids use a larger
first-row focus-safe inset. The scroll target itself now also includes focus
clearance, preventing top alignment from consuming that protection — see
[010-focus-safe-scroll-targets.md](010-focus-safe-scroll-targets.md).

Favorites and collection browsers retain their leading-control navigation
surface while content is loading or empty. An empty surface starts from its
active filter, allowing the next Left or Right command to move immediately.

Shared filter bars observe their semantic selection and center it in the
horizontal viewport. Runtime verification confirmed that later TV categories
remain visible in the app's narrow window and that empty Movies can move
directly to and activate empty People.
