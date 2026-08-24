# 003.009 — Section Selection Memory

## Context

Entering every destination section at target index zero is predictable, but it
discards the user's local navigation context. Repeatedly moving between two
collections then becomes unnecessarily expensive because each return starts
from the beginning.

The stable unit of memory is the semantic section or collection, not the source
column. Each section should therefore retain its own last valid target.

## Change

- Keep an independent last-selected target for every semantic section.
- Restore that target when Up or Down re-enters the section.
- Use target index zero only when a section has never been visited or its
  remembered target no longer exists.
- Update the remembered target after both keyboard selection and pointer-to-
  keyboard handoff.
- Reconcile section memory whenever dynamic content changes so stale model
  identifiers cannot become navigation targets.
- Apply the same contract to Home shelves, detail sections, poster-grid leading
  actions and content, and Favorites tabs and people.

## Validation

- Select nonzero targets in two Home shelves, move between them, and verify each
  shelf restores its own previous target.
- Repeat between detail sections and between a poster grid and its leading
  controls.
- Remove or empty a remembered collection and verify navigation safely falls
  back to the first valid target.
- Hand a hovered target to keyboard navigation, leave its section, and verify
  returning restores that target.
- Build the macOS application, run package tests, and run `git diff --check`.

## Current state

Implemented in the current working tree.

Home and detail focus graphs retain a stable target for every section ID.
Poster grids independently remember content and leading-control selections, and
Favorites people independently remember people and tabs. Pointer handoff writes
the same memory used by subsequent directional movement.

Every dynamic graph filters remembered identifiers against the latest model
snapshot. Invalid memory is removed, and the next entry falls back to the first
valid target or the active filter where one exists.
