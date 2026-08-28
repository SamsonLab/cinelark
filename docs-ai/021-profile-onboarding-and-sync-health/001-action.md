# 021 — Profile Onboarding and Sync Health: Action

| | |
| --- | --- |
| **Status** | Implemented and verified locally |
| **Date** | 2026-08-28 |
| **Scope** | Pending-import recovery, local-first continuation, and CloudKit transport health |

## Implemented

- Added `AppFeature.BootstrapState.waitingForCloud` and a dedicated root surface
  that explains why CineLark is waiting, shows the safe provisional Profile,
  and offers **Recheck iCloud** or **Continue Offline**.
- Continue Offline persists only the Local provisional Profile selection. The
  parent then routes the existing selection delegate through Source runtime
  restoration; `sourcesRestored` remains the only transition to ready.
- Added `ProfileCloudSyncStatus` with local-only, checking, synchronizing,
  available, and failed phases plus active setup/import/export operations, last
  successful event time, and redacted recovery guidance.
- `ProfileChangeHub` now tracks persistent-container events and emits a small
  sync-status invalidation. `ProfileFeature` re-queries through its dependency
  client; no CloudKit event or managed object enters TCA State.
- Added an iCloud Sync section to Profiles & Sources Settings with transport
  state, current activity, latest successful event, automatic-retry guidance,
  and a truthful recheck action.
- Scoped both initial-import and event-history requests with `affectedStores`
  to the Cloud persistent store. This prevents the Local store in the dual-store
  coordinator from receiving an unsupported CloudKit event request.

## Validation

- TDD red: the focused package test failed because the sync-health value and
  resolver did not exist.
- `ProfileCloudSyncStatus` resolver coverage verifies account-unavailable,
  pending import, active export, successful idle, and failed projections.
- `ProfileFeatureTests` verifies dependency-backed status refresh and
  provisional continue-offline selection.
- `AppFeatureTests.bootstrapWaitsForCloudWithRecovery` verifies Library remains
  hidden while import is pending and becomes ready only after the recovery path
  traverses Source restoration.
- An unsigned focused test launch reproduced an Objective-C exception when the
  event-history request was not store-scoped. The same launch and full suite
  pass after restricting `affectedStores` to the Cloud store.
- `swift test` passes 58 package tests.
- Unsigned `xcodebuild ... test` passes 35 Swift Testing tests across 13 suites
  and 6 XCTest cases.
- `git diff --check` passes.

## Deviations from the plan

- Historical successful-event time remains available. The initial unscoped
  implementation was briefly removed after reproducing a dual-store crash, then
  restored safely once the request was explicitly limited to the Cloud store.

## TCA learning review

Added `L021 — Recovery paths must re-enter the original readiness barrier`.
It captures the reusable rule that degraded-mode intent may relax a
prerequisite but must not create a second direct-to-ready transition.

## Remaining release gate

- The status is transport evidence, not convergence proof. Signed two-device
  validation for delayed import, offline writes, merge, tombstones, reinstall,
  and account transitions remains required.
