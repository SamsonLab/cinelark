# 014.004 — Viewing Facts and Device Records

## Context

`PlaybackState` is a mutable UI projection. It cannot answer how much time was
actually watched in a month, how many distinct viewing sessions occurred, or
which friendly device produced the activity after later progress overwrites the
same media row. The bootstrap UI also exposes a raw mutation-author identifier
because no synced device presentation record exists.

## Change

- Add Cloud `DeviceRecord`, `ViewingSession`, and `ProfilePlaybackEvent`
  entities plus Local provisional counterparts. Provisional playback facts must
  follow the same storage routing and promotion rules as favorite/playback
  projections.
- Use one `DeviceRecordID` per installation while retaining `ClientID` as the
  mutation author and provider device identity. Device records contain only a
  friendly name, platform description, and last-seen timestamp.
- Treat `ProfilePlaybackEvent` as append-only facts keyed by stable event ID.
  Record started, checkpoint, paused, resumed, stopped, and completed events.
- Treat `ViewingSession` as the rebuildable per-playback aggregate keyed by the
  player playback ID. It stores start/end timestamps, positions, monotonic
  watched seconds, completion status, and the producing device.
- Keep `PlaybackState` as the fast UI projection. One repository transaction
  persists projection, media snapshot, session update, device record, and event
  before optional provider mirroring.
- Compute Profile manifest session count, watch time, last activity, and last
  friendly device from viewing facts rather than progress snapshots.
- Preserve facts through provisional promotion and Profile merge. Composite
  `{profileID, factID}` persistence keys allow the same stable source fact to be
  copied into a merge target without deleting source history.

## Validation

- Repository tests cover append idempotence, mutation ordering, provisional
  promotion, Profile merge, manifest totals, and friendly-device projection.
- `PlaybackFeature` tests use `TestClock` to prove pause-aware monotonic watch
  accounting and the started/checkpoint/completed event sequence.
- Existing local-first, Cloud bootstrap, provider reporting, and mirror tests
  remain green.
- Signed two-device CloudKit validation remains a release gate.

## Current state

Implemented and locally validated on 2026-08-27. See
[`005-action.md`](005-action.md). Signed multi-device CloudKit validation
remains a release gate.
