# 025 — Single Personal Profile: Action

| | |
| --- | --- |
| **Status** | Implemented and verified locally |
| **Date** | 2026-08-28 |
| **Scope** | Canonical identity, automatic consolidation, local-first bootstrap, and simplified sync UX |

## Implemented

- Added a fixed `.personal` `ProfileID`. The identifier is account-scoped by
  the private CloudKit database rather than generated independently per device.
- New installations create the canonical Profile in the Local provisional
  graph. Pending or unavailable CloudKit state remains usable immediately.
- Cloud-ready bootstrap ensures the canonical record exists and automatically
  merges every visible legacy cloud Profile plus the device's provisional facts
  into it. No active-selection, creation-date, or display-name heuristic chooses
  the target.
- Merge now preserves import markers and migrates local Source bindings,
  selections, and queued mirror mutations. Existing target binding identity is
  retained while mirror intent is preserved if either binding enabled it.
- Replaced array-valued bootstrap/feature Profile state with one Profile and one
  manifest. Removed Profile create, switch, attach, keep-separate, and manual
  merge actions plus their root surfaces and client APIs.
- Settings now presents one Personal Viewing summary, a compact iCloud status,
  last successful transport event, and one recheck action. CloudKit checking no
  longer blocks Source restoration or browsing local history.

## Validation

- Full `CineLarkKit` SwiftPM suite: 70 tests passed.
- Full unsigned macOS suite: 41 Swift Testing tests across 14 suites plus 6
  XCTest cases passed.
- The macOS app target built successfully with code signing disabled.
- Tests prove stable identity, idempotent legacy consolidation, preservation of
  facts across two legacy Profiles, provisional local-first startup, absence of
  a Profile-choice readiness state, and unchanged Source-restoration gating.
- `git diff --check` passed.

## Deviations from plan

- `ProfileID` remains on every persisted fact and legacy merge records remain
  hidden rather than being physically deleted, as planned.
- CloudKit transport health remains a separate value projection. Bootstrap no
  longer carries a redundant resolution enum because there is no product
  decision to resolve.

## Remaining release gate

- Execute the existing signed two-device CloudKit convergence runbook. Local
  and in-memory evidence does not prove production CloudKit scheduling.
