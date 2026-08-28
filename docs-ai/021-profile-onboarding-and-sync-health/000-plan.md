# 021 — Profile Onboarding and Sync Health: Plan

| | |
| --- | --- |
| **Status** | Implemented and verified locally |
| **Anchor date** | 2026-08-28 |
| **Primary refs** | Pending |
| **Related** | [Viewing identity and sync](../014-viewing-identity-and-sync/000-plan.md), [Profile CloudKit schema](../../docs/interfaces/profile-cloudkit-schema.md), [TCA application architecture](../010-tca-application-architecture/000-plan.md) |

## Background

The repository already keeps a fresh Profile provisional until CloudKit import
readiness is known and presents an explicit merge/attach/keep-separate choice
when multiple histories exist. Two product gaps remain:

- an available iCloud account with a still-pending initial import leaves the
  root on a generic launch spinner with no local-first recovery path;
- Settings shows Profile manifests but not whether the local replica is
  checking, synchronizing, current, local-only, or blocked by a transport
  failure.

CloudKit synchronization remains system-managed. CineLark must expose truthful
health and retry/recheck controls without claiming to force a server sync.

## Goals

- Add a semantic application bootstrap state for pending CloudKit readiness.
- Present the provisional Profile summary while checking iCloud, with explicit
  recheck and continue-offline actions.
- Continue offline against the Local provisional graph without publishing it or
  discarding later Profile resolution.
- Project account availability and persistent-container event activity into a
  small, value-typed sync-health model.
- Show sync health, last successful transport event, local-first guarantees,
  and a recheck action in Profiles & Sources Settings.
- Turn CloudKit notifications into invalidations; do not place Core Data or
  CloudKit event objects in TCA state.
- Cover the readiness barrier, offline continuation, status refresh, and
  failure presentation with pure resolver and `TestStore` tests.

### Non-goals

- Replacing `NSPersistentCloudKitContainer` with `CKSyncEngine`.
- Adding a fake manual-sync API; the retry action only rechecks current state
  and lets the persistent container continue its normal work.
- Treating CloudKit transport success as proof of cross-device convergence.
- Allowing local-only continuation to publish or merge a provisional Profile.
- Removing the signed two-device release gate.

## Design / Approach

`ProfileCloudSyncStatus` is a pure value containing a presentation phase,
availability, last successful event date, and a redacted failure message. The
repository derives it from account/import availability plus a lock-protected
snapshot of `NSPersistentCloudKitContainer` setup/import/export events.

`ProfileChangeHub` retains only transport facts needed for projection and emits
`ProfileRepositoryChange.cloudSyncStatus`. `ProfileFeature` responds by calling
the dependency client and receives the value through an internal Action. Event
objects and notifications stay below the dependency boundary.

`AppFeature.BootstrapState.waitingForCloud` owns the readiness barrier. The root
renders a dedicated checking surface. Continue Offline persists selection of
the provisional Profile, restores local Source runtimes through the existing
barrier, and reveals Library. A later repository bootstrap invalidation may
still transition to normal synchronization or the explicit Profile-choice UI.

## Alternatives & decisions

- **Keep the generic launch spinner:** rejected because pending initial import
  is a recoverable semantic state, not ordinary loading.
- **Automatically continue after a timeout:** rejected because time does not
  prove whether an existing iCloud history will arrive.
- **Force CloudKit synchronization from Settings:** rejected because
  `NSPersistentCloudKitContainer` exposes event observation, not a supported
  force-sync command.
- **Store CloudKit events in TCA State:** rejected because only a stable domain
  projection is observable business state.

## Validation

- Resolver tests cover local-only, checking, active import/export, current, and
  failed transport projections.
- `ProfileFeature` tests cover status refresh and continue-offline selection.
- `AppFeature` tests prove pending import does not reveal Library until the user
  explicitly continues and Source restoration completes.
- Full SwiftPM and unsigned macOS test suites remain green.
- Signed two-device validation remains a separate milestone.

## Amendments

- None.
