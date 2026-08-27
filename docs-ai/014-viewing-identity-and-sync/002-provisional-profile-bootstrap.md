# 014.002 — Provisional Profile Bootstrap

## Context

The identity foundation prevents `ClientID`/`ProfileID` conflation but the live
application still creates an empty cloud-backed Profile before Core Data has
confirmed its initial CloudKit import. A correct first-install flow must retain
all provisional user state locally until the cloud account and Profile set are
known.

## Change

- Add Local-store entities for a provisional Profile, favorite/playback state,
  and media snapshots. Repository reads and writes route by Profile ownership;
  provisional facts never enter the Cloud configuration.
- Determine cloud availability from the iCloud account status plus completed
  `NSPersistentCloudKitContainer` import events. A successful import emits a
  bootstrap repository change.
- Promote a provisional Profile idempotently when CloudKit is confirmed empty.
  Copy cloud facts first, then remove local provisional records.
- Add attach, merge, and keep-separate Profile resolution commands. Attaching a
  fresh provisional Profile discards only empty provisional data; merging uses
  the existing non-destructive merge marker; keep-separate promotes it.
- Make `AppFeature` own application readiness. It restores Source runtimes and
  reveals Library only after Profile bootstrap is resolved.
- Present cloud Profile manifests in the root resolution surface with last
  activity, device, and saved-data summaries.

## Validation

- Repository tests prove provisional facts use Local entities, promotion is
  idempotent, and cloud facts remain isolated before promotion.
- Bootstrap tests cover unavailable/pending/empty/matching/different Profile
  sets, idempotent promotion, and idempotent provisional merge.
- `TestStore` proves application readiness remains blocked until Profile
  resolution and Library context is not applied before Source restoration.
- Signed two-device CloudKit validation remains a release gate.

## Current state

Implemented on 2026-08-27. See [`003-action.md`](003-action.md).
