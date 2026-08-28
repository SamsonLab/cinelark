# 023 — CloudKit Convergence Validation: Action

| | |
| --- | --- |
| **Status** | Harness implemented and verified locally; physical execution pending |
| **Date** | 2026-08-28 |
| **Scope** | Redacted replica audits, signed-app capture, entitlement preflight, and operator runbook |

## Implemented

- Added a deterministic schema-v1 Profile audit over profiles, favorites,
  playback projections, media snapshots, viewing sessions, playback events,
  devices, and CloudKit transport state.
- Canonical sorting plus SHA-256 digests prove fact equality without exporting
  raw Profile IDs or names, media keys, titles, artwork URLs, device names,
  provider locators, server addresses, or credentials.
- Added an environment-gated app capture path. It disables Sparkle startup,
  skips normal TCA bootstrap and Remote/IINA services, waits a bounded settle
  window, writes one audit atomically, and terminates.
- Added `scripts/validate_cloudkit_sync.sh` with strict signed-app entitlement
  preflight, non-overwriting capture, redacted schema validation, and two-replica
  convergence comparison.
- Added a physical two-device runbook for delayed import, offline writes,
  concurrent conflicts, Profile merge, tombstones, reinstall, and account
  transitions. Destructive and security-sensitive operator actions remain
  explicitly manual.

## Validation

- TDD red: the repository audit test initially failed because no audit snapshot
  contract existed.
- TDD red: the macOS launch test initially failed because no environment parser
  existed.
- The audit test proves insertion-order independence, mutation sensitivity, and
  absence of supplied private fixture strings in encoded output.
- `swift test --package-path packages/apple/CineLarkKit` passes 63 tests.
- Unsigned macOS tests pass 37 Swift Testing tests across 14 suites and 6 XCTest
  cases.
- `bash -n scripts/validate_cloudkit_sync.sh` passes. A synthetic self-compare
  passes, while a changed dataset digest fails with the expected convergence
  error.
- A signed Debug build was attempted with automatic provisioning. Xcode rejected
  it because the available Personal Team cannot provision iCloud and Push
  Notifications for `com.samsonlab.cinelark`; therefore signed entitlement
  preflight and live local capture were not represented as completed.
- `git diff --check` passes.

## Deviations from the plan

- Local signed capture could not run on this host because a capable Apple
  Developer Team provisioning profile is unavailable. The harness is ready for
  the maintainer signing environment.
- The physical two-device matrix remains a release gate. One machine cannot
  establish replica convergence or safely automate iCloud account/network/app
  lifecycle scenarios.

## TCA learning review

No entry was added. The capture path intentionally bypasses normal application
bootstrap and exposes no product state; the reusable work belongs to the
repository and release-validation boundary rather than a new TCA pattern.

## Remaining release gate

- Build or export CineLark with a Team that supports the configured CloudKit
  container, then run every scenario in the convergence runbook on two physical
  Macs and retain both immutable audit files outside the repository.
