# 014 — Viewing Identity and Sync: Plan

| | |
| --- | --- |
| **Status** | Implemented locally — signed physical convergence remains a release gate |
| **Anchor date** | 2026-08-27 |
| **Primary refs** | [`005-action.md`](005-action.md), [`../021-profile-onboarding-and-sync-health/001-action.md`](../021-profile-onboarding-and-sync-health/001-action.md), [`../023-cloudkit-convergence-validation/001-action.md`](../023-cloudkit-convergence-validation/001-action.md), [`../024-local-recommendations/001-action.md`](../024-local-recommendations/001-action.md), [`../025-single-personal-profile/001-action.md`](../025-single-personal-profile/001-action.md) |
| **Related** | [`../../docs/decisions/0011-personal-viewing-memory.md`](../../docs/decisions/0011-personal-viewing-memory.md), [`../../docs/interfaces/profile-cloudkit-schema.md`](../../docs/interfaces/profile-cloudkit-schema.md), [`../011-media-source-platform/000-plan.md`](../011-media-source-platform/000-plan.md) |

## Background

The first Profile implementation conflates a locally generated device string
with mutation authorship and resolves concurrent records using wall-clock time.
It also creates the first cloud-backed Profile as soon as the local projection
appears empty. On a fresh installation, CloudKit import can still be pending,
so that behavior can create duplicate Profiles and cannot support an informed
choice between existing iCloud histories.

CineLark's durable product identity is the user's personal viewing memory, not
an Emby server account. One iCloud private database may therefore contain
multiple CineLark Profiles, while each configured media account retains an
independent remote playback record.

## Goals

- Separate installation/client, device record, Profile, Source, remote user,
  content, and locator identities.
- Model first-run bootstrap as an explicit state machine that distinguishes an
  empty cloud from a pending or unavailable cloud import.
- Allow a provisional local Profile to attach to, merge into, or remain
  separate from existing cloud Profiles without replacing the client ID.
- Expose enough Profile manifest data to make resolution understandable:
  recent activity, last device, title/session/favorite counts, and watch time.
- Replace wall-clock latest-wins with a deterministic, locally monotonic
  mutation stamp while retaining UTC timestamps for analytics and display.
- Keep CineLark viewing memory and Emby user state independent. Local writes
  remain authoritative; standard Emby playback reporting is an ordered,
  best-effort remote mirror.
- Deliver the first tested vertical slice through pure identity, mutation-clock,
  bootstrap-resolution, and merge contracts before wiring CloudKit runtime UI.

### Non-goals

- Cross-Apple-ID Profile sharing or household permissions.
- Uploading Source credentials, base URLs, tokens, or signed playback URLs.
- Collaborative filtering or a CineLark recommendation backend.
- Treating CloudKit synchronization as immediate or network availability as a
  prerequisite for local playback.
- Supporting UHDNow-private endpoints in the standard Emby runtime.

## Design / Approach

1. `ClientID` identifies one CineLark installation and is stored locally. It is
   used as the Emby `DeviceId` and mutation author; it is never replaced by a
   cloud Profile choice.
2. `ProfileID` identifies one durable viewing history inside the user's iCloud
   private database. A local `ActiveProfileSelection` binds the client to one
   Profile without syncing that selection.
3. A provisional Profile remains in the Local store until bootstrap resolves.
   A confirmed empty cloud promotes it. Existing manifests require attach,
   merge, or keep-separate resolution when the local Profile has meaningful
   data.
4. Merge writes an idempotent import marker and a source-to-target merge marker.
   Source facts are retained until validation; destructive cleanup is deferred.
5. `MutationStamp` is a hybrid logical clock tuple of UTC milliseconds,
   logical counter, and client ID. UTC event timestamps remain separate and are
   formatted in the viewer's current locale/time zone.
6. Append-oriented viewing facts merge by stable event ID. Mutable projections
   use their mutation stamp. Deletions synchronize as tombstones instead of
   immediate physical deletion.
7. Profile manifests are small summaries for bootstrap UX. Exact statistics
   remain rebuildable from viewing facts; manifest counters are eventually
   consistent presentation data.
8. Playback actions append CineLark facts and independently enqueue the standard
   Emby Started/Progress/Stopped lifecycle. Remote failure never rolls back the
   local record.

## Alternatives & decisions

- Replacing the local client ID with a cloud ID was rejected because it erases
  device authorship and breaks Emby device/session identity.
- Raw `Date` latest-wins was rejected because UTC does not prevent clock skew or
  backward wall-clock movement.
- Creating a cloud Profile whenever the local mirror is empty was rejected
  because CloudKit initial import is system-scheduled.
- Automatically folding Emby user state into CineLark was rejected because the
  same remote account can outlive, replace, or conflict with a personal viewing
  history. Import remains explicit and outbound reporting remains independent.
- Migrating all persistence to `CKSyncEngine` was deferred. The existing
  `NSPersistentCloudKitContainer` local-replica model remains appropriate; a
  small explicit manifest index may be added only if first-run discovery cannot
  meet the UX contract through container import events.

## Validation

- Identity tests prove Profile selection never changes `ClientID`.
- Mutation-clock tests cover equal time, backward time, remote observation, and
  deterministic client-ID tie-breaking.
- Bootstrap tests cover cloud unavailable, pending import, confirmed empty,
  matching Profile, attach, merge, and keep-separate outcomes.
- Repository tests cover idempotent merge, tombstone precedence, and legacy
  record fallback.
- TCA `TestStore` tests cover resolution presentation and cancellation of stale
  bootstrap work.
- A signed two-device CloudKit smoke test remains required before release.

## Amendments

- Updated 2026-08-28: Product ownership was narrowed to one stable personal
  Profile per private iCloud account; fact-level convergence remains unchanged —
  see [025 — Single personal Profile](../025-single-personal-profile/000-plan.md).

- Updated 2026-08-28: Sync recovery, deterministic audit capture/comparison,
  cached historical enrichment, and private local recommendations are
  implemented. The repository has completed all automatable work for this
  milestone; the remaining two-Mac signed runbook is an external release gate.

- Updated 2026-08-27: The first vertical slice implemented typed client
  identity, persistent mutation stamps, manifests, deterministic bootstrap
  resolution, non-destructive merge, and tombstones. CloudKit readiness and
  provisional local data remain the next slice — see
  [`001-action.md`](001-action.md).
- Updated 2026-08-27: Implement Local-store provisional facts, CloudKit import
  readiness, promotion, and the TCA resolution surface — see
  [`002-provisional-profile-bootstrap.md`](002-provisional-profile-bootstrap.md).
- Updated 2026-08-27: The provisional bootstrap amendment is implemented and
  validated locally — see [`003-action.md`](003-action.md).
- Updated 2026-08-27: Add synced device presentation plus append-oriented
  playback facts and rebuildable viewing sessions — see
  [`004-viewing-facts-and-device-records.md`](004-viewing-facts-and-device-records.md).
- Updated 2026-08-27: The viewing-facts amendment is implemented and locally
  validated — see [`005-action.md`](005-action.md).
