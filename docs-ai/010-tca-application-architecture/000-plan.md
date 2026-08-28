# 010 — TCA Application Architecture: Plan

| | |
| --- | --- |
| **Status** | Implemented — application Feature ownership migration complete |
| **Anchor date** | 2026-08-26 |
| **Primary refs** | [`001-action.md`](001-action.md), [`../../docs/decisions/0010-tca-application-boundary.md`](../../docs/decisions/0010-tca-application-boundary.md) |
| **Related** | [`TCA-learn.md`](TCA-learn.md), [`../003-keyboard-first-navigation/000-plan.md`](../003-keyboard-first-navigation/000-plan.md), [`../../docs/architecture.md`](../../docs/architecture.md) |

## Background

CineLark currently distributes application state across SwiftUI-local state,
several `@Observable` models, navigation bindings, shortcut callbacks, and
long-lived gateway tasks. That shape served the first UHDNow vertical slice but
does not provide one deterministic owner for navigation, profiles, media
sources, playback orchestration, or future multi-protocol features.

## Goals

- Adopt The Composable Architecture as the sole application and feature-layer
  state-management convention.
- Preserve pure Swift concurrency boundaries for domain, persistence, media
  source plugins, playback engines, and native gateways.
- Move incrementally, with exactly one state owner for every migrated feature.
- Make effect lifetime, cancellation, dependency injection, and state-machine
  testing explicit.
- Maintain a concise, evidence-backed TCA learning reference for future work.

### Non-goals

- Rewriting stable transport actors or provider adapters as reducers.
- Moving hover, animation, transient focus, or raw geometry into feature state.
- Introducing RxSwift or exposing Combine publishers as application contracts.
- Reproducing generic TCA documentation in the repository.

## Design / Approach

1. Pin TCA 1.26.1 and expose it only to the macOS feature layer.
2. Introduce `AppFeature` with child navigation, library, source, profile,
   playback, and remote features.
3. Use `StackState` for semantic detail navigation and TCA sharing for small
   device preferences such as sidebar visibility.
4. Wrap actors and services in value-typed dependency clients with `@Sendable`
   async closures and bounded `AsyncSequence` subscriptions.
5. Scope every long-lived effect with a cancellation identity; use latest-wins
   cancellation for search and replaceable queries.
6. Keep large catalog records outside Store state. Features retain stable IDs,
   query state, and lightweight presentation projections.
7. Migrate one vertical feature at a time and remove the superseded observable
   state owner in the same change.
8. Record only validated, reusable lessons in `TCA-learn.md`.

## Alternatives & decisions

- Native Observation plus a custom reducer/effect system was rejected because
  it would recreate dependency, cancellation, navigation, and test tooling.
- A permanent mixed TCA/observable architecture was rejected because it makes
  state ownership and lifecycle behavior ambiguous.
- A one-shot rewrite was rejected because existing focus, playback, and remote
  behavior contains verified lifecycle details that must migrate incrementally.

## Amendments

- Updated 2026-08-28: Profile, Source, Library, Search, Detail, Playback,
  Remote, Cache, and Insights are TCA-owned. The legacy observable application
  models and `MediaLibraryProvider` boundary have been removed. The final
  verified state is recorded in [`001-action.md`](001-action.md) and
  [`002-feature-ownership-migration.md`](002-feature-ownership-migration.md).

- Updated 2026-08-26: Continue the vertical migration through Profile, Search,
  Detail, Playback, and Remote, removing each legacy observable owner after its
  replacement is verified — see
  [`002-feature-ownership-migration.md`](002-feature-ownership-migration.md).
