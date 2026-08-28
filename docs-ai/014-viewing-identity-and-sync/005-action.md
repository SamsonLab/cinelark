# 014.005 — Viewing Facts and Device Records Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-27 | Added Cloud and provisional device/session/event entities | [`004-viewing-facts-and-device-records.md`](004-viewing-facts-and-device-records.md) |
| 2026-08-27 | Routed playback lifecycle edges through one local-first write bundle | [`../010-tca-application-architecture/TCA-learn.md`](../010-tca-application-architecture/TCA-learn.md#l016--persist-one-semantic-lifecycle-edge-as-one-domain-write-bundle) |
| 2026-08-27 | Projected durable session and friendly-device facts into Profile manifests and Settings | [`../../docs/interfaces/profile-cloudkit-schema.md`](../../docs/interfaces/profile-cloudkit-schema.md) |

## Outcome & current state (as of 2026-08-27)

- `DeviceRecord` separates friendly device presentation from `ClientID`, while
  retaining the installation identity as the mutation and Emby device author.
- `ViewingSession` is a mutation-ordered, rebuildable aggregate for one player
  playback ID. `ProfilePlaybackEvent` is an immutable fact keyed by a stable
  event ID and records started, checkpoint, pause, resume, stop, and completion.
- Cloud and provisional Local configurations contain equivalent fact entities.
  Playback routing, provisional promotion, provisional merge, and Cloud Profile
  merge preserve session/event/device records with composite Profile keys.
- Session and event reads fold physical rows by stable domain ID and mutation
  stamp, preventing a duplicate CloudKit merge row from inflating statistics.
- `ProfilePlaybackWrite` atomically persists Resume projection, media snapshot,
  session, event, and device activity before independent provider reporting.
- `PlaybackFeature` tracks only lightweight active-session accounting. Paused
  movement, backward seeks, and forward jumps larger than 30 seconds do not
  inflate watched seconds.
- Profile manifests now derive session count, watch time, last activity, and
  friendly last-device name from viewing facts. Settings exposes the session
  count and formatted watch time.
- Device last-seen writes are throttled to one hour when name and platform are
  unchanged, avoiding unnecessary CloudKit churn during bootstrap and playback.

## Validation

- `swift test --package-path packages/apple/CineLarkKit`: 63 tests across 7
  suites pass. New coverage proves immutable event idempotence, mutation-ordered
  session updates, manifest totals, friendly-device projection, provisional
  promotion, and Profile merge preservation.
- Unsigned `xcodebuild ... test` passes all 26 macOS tests, including
  `PlaybackFeatureTests.lifecycleReporting` and
  `PlaybackFeatureTests.pauseAwareWatchAccounting`.
- `git diff --check` passes for the milestone changes.
- Signed two-device CloudKit validation was not run and remains a release gate.

## Deviations from plan

- `ViewingSession` is intentionally mutable by stable session ID and mutation
  stamp; only `ProfilePlaybackEvent` is append-only. This keeps frequent
  checkpoints compact while preserving rebuildable lifecycle facts.
- Watch accounting currently derives from bounded player-position deltas. It
  measures consumed media time and rejects seek jumps; wall-clock engagement
  time can be added later as a separate metric without changing event identity.
- Settings exposed durable totals and the friendly last device at this
  milestone. Account/transport health and pending-import recovery were added
  later by
  [021 — Profile onboarding and sync health](../021-profile-onboarding-and-sync-health/001-action.md).

## Follow-up

- Run signed two-device scenarios for delayed import, offline writes, merge,
  tombstones, reinstall, and iCloud account transitions.
- Add an insight projection layer that derives monthly, quarterly, annual,
  person, director, and genre summaries from immutable playback events plus
  Catalog metadata.
- Signed-device convergence remains unverified; the status surface intentionally
  reports transport evidence rather than claiming cross-device convergence.
