# 029 — Maintainability Boundaries: Action

| | |
| --- | --- |
| **Status** | Implemented |
| **Completed** | 2026-08-31 |
| **Plan** | [000-plan.md](000-plan.md) |

## Outcome

The identified Profile, Emby, Remote, and macOS presentation hotspots now expose
clearer ownership seams without changing their public contracts or introducing new
runtime dependencies. The repository actor, account-bound Emby actor, Remote
coordinator lifecycle, and TCA feature ownership remain intact.

## Implemented

- Extracted Profile change observation, store schema construction, and convergence
  operations into focused files while retaining one actor and transaction context.
- Grouped Emby browsing, playback, and mutations in actor extensions; transport,
  account state, and mapping helpers remain owned by the same service.
- Extracted Remote capability advertisement and routing into a pure policy with direct
  coverage that every routed capability is advertised.
- Split Home/catalog shelves and media-detail playback components from their prior
  presentation files without introducing duplicate navigation state.
- Regenerated the Xcode project from `apps/macos/project.yml` so all extracted app and
  test sources are explicit project members.

## Boundary evidence

| Hotspot | Before | Result |
| --- | ---: | --- |
| Profile repository | 2,606 lines | 1,330-line repository, 822-line convergence extension, 293-line schema, 179-line change hub |
| Emby service | 994 lines | 438-line core actor plus 306/153/115-line domain extensions |
| Catalog library views | 1,110 lines | 670-line Home file plus 444-line browse components |
| Media detail views | 1,710 lines | 1,053-line detail file plus 661-line detail components |
| Remote coordinator | 864 lines | 840-line lifecycle/I/O coordinator plus 38-line pure capability policy |

## Verification

- `swift test --package-path packages/apple/CineLarkKit`: 73 passed, 0 failed.
- macOS `xcodebuild test` with signing disabled: 60 passed, 0 failed.
- Xcode project regeneration with `xcodegen`: succeeded.
- Script syntax, documentation links, and final whitespace validation: passed.

## Deviations and limits

- `CoreDataProfileRepository.swift` remains slightly above the approximate 1,200-line
  review signal. Further splitting would separate tightly coupled persistence
  transactions from their actor owner; the largest independent convergence and schema
  responsibilities were extracted instead.
- Remote payload decoding remains in `RemoteCoordinator`. At 840 lines it is below the
  review signal, and extracting only capability policy produced a genuinely pure seam
  without adding a generic command framework.
- Existing uncommitted work was preserved throughout; this change did not reformat or
  clean unrelated files.
