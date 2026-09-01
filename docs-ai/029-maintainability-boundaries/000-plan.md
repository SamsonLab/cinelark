# 029 — Maintainability Boundaries: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-31 |
| **Primary refs** | [Implementation outcome](001-action.md) |
| **Related** | [TCA application architecture](../010-tca-application-architecture/000-plan.md), [Media source platform](../011-media-source-platform/000-plan.md), [Architecture](../../docs/architecture.md) |

## Background

CineLark's compile-time module graph is healthy, but several implementation files now
combine multiple independently changing responsibilities. The largest concentrations
are Profile persistence and convergence, Emby browsing/playback/mutation mapping,
Remote command routing and snapshot projection, and macOS catalog/detail presentation.
Their tests protect behavior, but file-local coupling increases review cost and makes
parallel changes conflict-prone.

## Goals

- Preserve every public and package-facing behavior while reducing responsibility
  concentration in the identified hotspots.
- Split by stable ownership seams rather than arbitrary line count.
- Keep Core Data objects, provider DTOs, gateway transports, and SwiftUI state inside
  their existing architectural boundaries.
- Add focused tests where extraction creates a pure policy or projection seam.
- Keep individual production source files below roughly 1,200 lines when a coherent
  split exists; treat this as a review signal, not a mechanical build gate.

### Non-goals

- Redesigning Profile identity, CloudKit conflict policy, Emby contracts, Remote wire
  messages, or media-detail behavior.
- Introducing another package, runtime dependency, repository abstraction, or generic
  coordinator framework.
- Reformatting unrelated code or rewriting working reducers.
- Pursuing minimum file size at the cost of hidden coupling or excessive indirection.

## Design / Approach

### Profile persistence

Extract Core Data schema construction and CloudKit change observation from
`CoreDataProfileRepository`. The repository remains the actor and transaction owner;
the extracted types remain internal to `CineLarkProfile`.

### Emby adapter

Keep one account-bound `EmbyService` actor while grouping browsing, playback,
mutation, transport, and mapping operations into extensions/files. Stored session
state remains actor-isolated and provider DTOs remain inside `CineLarkEmby`.

### Remote coordination

Extract pure capability lookup and payload/projection policy from the main-actor
coordinator. The coordinator continues to own lifecycle, UI activation, gateway I/O,
and mutable revisions.

### macOS presentation

Move independent Home/category/collection/favorites views and playback-option/detail
components into focused files. Semantic keyboard navigation remains owned by its
current surface until a separately tested navigation model justifies extraction.

## Validation

- Existing Swift Package and macOS application suites remain green.
- Add focused tests for extracted pure policies where behavior was previously private
  and implicit.
- Build the unsigned macOS application and run `git diff --check`.
- Compare source-file size and dependency direction before and after the change.

## Alternatives & decisions

- **Create more SwiftPM targets:** rejected for now; measured ownership pressure is
  inside existing modules, not between them.
- **Split only by file length:** rejected because it preserves coupling while hiding it.
- **Rewrite the persistence layer:** rejected; the current actor and Core Data model
  have valuable convergence coverage.
- **Extract all SwiftUI keyboard logic immediately:** rejected because the current
  interaction restoration is recent and should first stabilize behind existing tests.

## Amendments

- None.
