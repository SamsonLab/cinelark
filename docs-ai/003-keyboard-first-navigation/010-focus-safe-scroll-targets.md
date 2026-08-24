# 003.010 — Focus-Safe Scroll Targets

## Context

Search and Favorites added top content padding to protect the first poster row
from focus scaling. Directional selection still calls `scrollTo(itemID,
anchor: .top)`, however, which aligns the identified poster lockup itself to the
scroll viewport boundary. That alignment consumes the surrounding padding and
lets the scaled artwork and focus stroke extend into the ScrollView clip.

Focus clearance is therefore a property of the scroll target geometry, not only
of the collection's outer spacing.

## Change

- Identify a poster-row wrapper that includes explicit focus clearance above
  the poster instead of identifying the poster lockup directly.
- Scroll the wrapper to the viewport top so the artwork remains inset after
  every directional selection, including non-first rows.
- Reduce inter-row layout spacing by the same clearance amount so visual row
  rhythm and the configured first-row inset remain unchanged.
- Keep the solution inside `PosterGrid` so Search, Favorites, and other poster
  collections share one invariant.

## Validation

- Select the first Search result and verify its top focus stroke and rounded
  corners remain fully visible.
- Repeat in Favorites and after moving to lower rows that require scrolling.
- Verify pointer hover uses the same unclipped clearance at the first row.
- Build the macOS app, run package tests, and run `git diff --check`.

## Current state

Implemented in the current working tree.

Every `PosterGrid` item now identifies a wrapper containing 18 points of focus
clearance above its poster lockup. Top-aligned directional scrolling therefore
aligns the wrapper rather than the transformed artwork.

Grid top padding and inter-row spacing subtract the same clearance, preserving
the configured first-row position and visual poster-to-poster rhythm. Runtime
verification confirmed complete top corners and focus strokes in Search,
Favorites first-row selection, and Favorites selection after scrolling to a
lower row.
