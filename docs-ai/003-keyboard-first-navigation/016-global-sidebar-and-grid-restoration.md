# 003.016 — Global Sidebar and Grid Restoration

## Context

Media and person detail destinations currently force the split view to
`detailOnly` on appearance and back to `all` on disappearance. This overwrites
the user's sidebar choice and changes the collection width during a navigation
round trip. Poster grids recompute their column count from that width but retain
only internal selection state, so the visible position can shift on return.

## Change

- Make sidebar visibility semantic application state owned by the root TCA
  feature and persisted as a user preference.
- Never mutate that preference from a detail destination lifecycle callback.
- Keep temporary system collapse caused by window geometry separate from the
  persisted preference.
- Promote collection selection and restoration anchors to library feature
  state. Preserve exact position when column geometry is unchanged and preserve
  the selected item as the visible anchor when it changes.

## Validation

- Reducer tests cover explicit sidebar toggles and navigation round trips.
- Grid restoration tests cover stable and changed column counts.
- A macOS runtime pass verifies Home, collection, media detail, and person
  detail navigation with both sidebar preferences.

## Current state

Planned as part of the TCA navigation vertical slice.

