# 023 — CloudKit Convergence Validation: Plan

| | |
| --- | --- |
| **Status** | Implemented locally; physical two-device execution pending |
| **Anchor date** | 2026-08-28 |
| **Primary refs** | [Action](001-action.md), [Runbook](../../docs/runbooks/cloudkit-convergence-validation.md) |
| **Related** | [Viewing identity and sync](../014-viewing-identity-and-sync/000-plan.md), [Profile CloudKit schema](../../docs/interfaces/profile-cloudkit-schema.md), [Local automatic release signing](../../docs/decisions/0007-local-automatic-release-signing.md) |

## Background

Profile conflict, merge, tombstone, and onboarding semantics have deterministic
repository and reducer coverage, but `NSPersistentCloudKitContainer` behavior
is still gated on signed multi-device validation. The repository lacks a
repeatable way to prove that two local replicas converged without exporting
titles, provider locators, Profile names, or other viewing history.

This milestone cannot manufacture a second physical Mac or change the user's
iCloud account automatically. It must make every safe local step executable,
verify the signed artifact, produce privacy-preserving evidence, and leave only
the genuine two-device interaction as an explicit physical release gate.

## Goals

- Add a deterministic, redacted audit snapshot over visible Profile facts.
- Include counts, mutation maxima, and SHA-256 dataset digests without raw
  Profile IDs, media keys, titles, people, URLs, device names, or provider data.
- Add an environment-gated signed-app capture mode that waits a bounded time
  for current CloudKit activity, writes one audit file, and exits without
  bootstrapping normal app services or mutating Profile facts.
- Add a shell harness to verify code signing and CloudKit entitlements, capture
  one replica, and compare two audit snapshots.
- Add a precise two-device runbook for delayed import, offline writes, merge,
  tombstones, reinstall, and account transitions.
- Run repository tests, signed-build entitlement preflight, and a local signed
  audit capture when the maintainer credentials and iCloud account permit it.

### Non-goals

- Automating iCloud sign-in/out, network disconnection, app deletion, or
  Application Support removal.
- Reading CloudKit records directly or treating transport events as convergence.
- Exporting raw viewing history or credentials into validation artifacts.
- Marking the physical two-device release gate complete from one local host.
- Adding production UI for internal release validation.

## Design / Approach

`ProfileSyncAuditSnapshot.capture(repository:capturedAt:)` queries the existing
repository contract. It sorts each fact family by stable semantic identity,
encodes canonical JSON, and emits SHA-256 digests plus counts and latest
mutation milliseconds. Only fingerprints and aggregate digests leave the
process. Device records contribute a count but not volatile last-seen values to
the convergence digest.

The app recognizes `CINELARK_CLOUDKIT_AUDIT_OUTPUT`. In this explicit mode its
root task does not send normal bootstrap actions or start Remote/IINA services.
It waits a bounded settle interval so a stale launch-time `upToDate` projection
cannot bypass a later import event, captures the final sync state and audit,
writes atomically to the requested path, and terminates. Normal launches are
unchanged.

`scripts/validate_cloudkit_sync.sh` supports:

- `preflight APP`: strict signature and entitlement verification;
- `capture APP OUTPUT`: refuse an already-running CineLark or existing output,
  launch the exact signed executable, and validate the redacted JSON shape;
- `compare A B`: require matching schema and Profile dataset digests while
  reporting only counts, phases, and pass/fail evidence.

## Alternatives & decisions

- **Dump Core Data/CloudKit records:** rejected because it exports sensitive
  history and can race a live persistent-store coordinator.
- **Compare only manifest counts:** rejected because equal counts do not prove
  equal favorites, progress, sessions, events, or snapshots.
- **Add a hidden Settings panel:** rejected because release validation is not a
  product workflow and would expand TCA state for operator tooling.
- **Automate store deletion or iCloud account changes:** rejected because those
  are destructive or security-sensitive operations requiring direct operator
  control on each physical device.

## Validation

- Pure tests prove deterministic output across insertion order, digest changes
  after a fact mutation, and absence of supplied raw private strings.
- Existing Profile repository tests remain green.
- Signed app preflight verifies Team-backed signing and the exact CloudKit
  container entitlement.
- Local capture produces schema-valid redacted JSON when account availability
  permits; otherwise the action record reports the precise external blocker.
- The runbook retains the two-device matrix until both replicas produce matching
  dataset digests after each scenario.

## Amendments

- None.
