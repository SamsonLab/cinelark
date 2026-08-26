# ADR 0010: TCA Owns the Application Layer

- **Status:** Accepted
- **Date:** 2026-08-26

## Decision

CineLark uses The Composable Architecture 1.26.1 as the sole convention for
feature state, application navigation, effect orchestration, and dependency
injection. The version is pinned exactly and upgraded only through an explicit
migration and full test pass.

Domain models, media plugins, Core Data/CloudKit repositories, playback engines,
and native gateways remain independent Swift concurrency components. TCA sees
them only through value-typed dependency clients.

## State ownership

- Semantic navigation uses `StackState`; destinations cannot change parent
  navigation from lifecycle callbacks.
- Durable device preferences use `@Shared` only when they are small scalar
  values. Responsive layout state remains local to SwiftUI.
- Feature state contains query identity, stable IDs, and lightweight
  presentation snapshots. Catalog rows, managed objects, transports, and plugin
  runtimes stay outside Store state.
- Replaceable requests use feature-scoped cancellation. Long-lived streams must
  define cancellation, buffering, replay, and termination behavior.

## Migration rule

A legacy observable model may be wrapped temporarily by a dependency client.
When a feature becomes authoritative, the old model loses ownership of that
state in the same milestone. Permanent dual writes are not allowed.
