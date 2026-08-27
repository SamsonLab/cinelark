# 018 — Emby Metadata Fidelity: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-27 | Added optional Emby metadata decoding and deterministic provider-neutral genre normalization | [`EmbyService.swift`](../../packages/apple/CineLarkKit/Sources/CineLarkEmby/EmbyService.swift) |
| 2026-08-27 | Preserved enriched summaries through Catalog and explicit Profile import | [`000-plan.md`](000-plan.md) |
| 2026-08-27 | Added dimension-complete Profile metadata merging | [`profile-cloudkit-schema.md`](../../docs/interfaces/profile-cloudkit-schema.md) |
| 2026-08-27 | Corrected hierarchy episode playback identity and expanded the detail presentation | [`TCA-learn.md`](../010-tca-application-architecture/TCA-learn.md#l019--child-delegates-must-carry-leaf-semantic-identity) |

## Outcome & current state (as of 2026-08-27)

- Emby browse, latest, resume, works, and detail requests explicitly ask for
  original title and genres instead of relying on server defaults.
- Item normalization retains original title, provider-order genres, series-only
  child count, and whole- or fractional-second last-played instants.
- Genre normalization provides deterministic local value identity without
  claiming a remote Emby genre ID or cross-source matching authority.
- Enriched summaries round-trip through the local Catalog. Detail presentation
  exposes original title, genres, duration, and season count when available.
- Ordinary browsing still projects the active local Profile as UI truth.
  Explicit remote import alone copies Emby last-played state and genres.
- Profile snapshot updates preserve an existing metadata dimension when a newer
  partial update omits it. Absence remains distinct from deletion until the
  schema defines metadata tombstones.
- Selecting a series hierarchy episode now sends its exact `.episode` identity
  to Playback and Profile orchestration.

## Validation

- The metadata fixture test initially reported nine mismatches before decoding,
  field requests, normalization, counts, and dates were implemented.
- The Profile repository regression test initially proved that a genre-only
  snapshot erased director and cast evidence; dimension-complete merging makes
  that test pass.
- `swift test` in `packages/apple/CineLarkKit`: 66 tests pass.
- Unsigned `xcodebuild ... CODE_SIGNING_ALLOWED=NO test`: all macOS application
  and TCA tests pass.
- A private read-only aggregate check found the observed series `ChildCount`
  equal to the corresponding seasons response count. No private title, ID,
  token, server path, or response payload entered the repository.
- `git diff --check` passes.

## Deviations from plan

- Implementation review exposed a second data-loss boundary not obvious from
  transport mapping: record-level snapshot replacement could erase richer
  contributor evidence. The plan was amended before adding repository merging.
- Profile genre snapshots intentionally omit `providerID`. The normalized
  integer is a CineLark presentation key, not a provider-issued identifier.
- The TCA learning archive gained L019 because the hierarchy playback bug is a
  reusable delegate-boundary lesson with direct `TestStore` evidence.

## Open questions

- Authenticated artwork still needs a header-aware SwiftUI loading surface.
- A future metadata deletion feature requires per-dimension tombstones or
  field-level mutation stamps; empty input is currently treated as incomplete.
- Historical Profile snapshots need an explicit enrichment/backfill workflow
  if metadata should appear without revisiting or replaying the item.
