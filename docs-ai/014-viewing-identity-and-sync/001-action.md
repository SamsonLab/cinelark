# 014 — Viewing Identity and Sync: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-27 | Accepted personal viewing memory as the durable product identity | [`../../docs/decisions/0011-personal-viewing-memory.md`](../../docs/decisions/0011-personal-viewing-memory.md) |
| 2026-08-27 | Implemented identity, mutation-clock, manifest, merge, and tombstone foundation | Working tree |

## Outcome & current state (as of 2026-08-27)

- `ClientID` is a typed local installation identity. The app migrates the
  existing `cinelark.device.id` preference to `cinelark.client.id` without
  changing the UUID, and the same value remains the Emby `DeviceId`.
- `ProfileID` remains independent. Selecting, merging, or synchronizing a
  Profile cannot replace `ClientID` through the dependency surface.
- Mutable Profile, favorite, playback, and media-snapshot records accept a
  backward-compatible `MutationStamp`. The repository persists stamp fields and
  uses them before the legacy `{modifiedAt, deviceID}` fallback.
- `MutationClockState` is stored in the Local Core Data configuration and emits
  monotonically increasing hybrid logical stamps across equal or backward wall
  time.
- `ProfileManifest` projects recent activity and the currently available title
  and favorite counts. Settings displays the active Profile summary. Session,
  watch-time, and named-device values remain zero/unknown until their durable
  entities exist.
- `ProfileBootstrapResolver` expresses unavailable, pending, empty, matching,
  and choice-required outcomes without importing TCA or CloudKit.
- Profile merge is idempotent by operation ID. Source favorite/playback facts
  remain available, target conflicts use original mutation stamps, and the
  merged source Profile is hidden rather than destroyed.
- Profile deletion now writes a tombstone instead of physically deleting the
  Profile graph.
- The contributor-facing schema and product statement now define personal
  viewing memory as source-independent and provider remote state as separate.

## Validation

- `swift test` in `packages/apple/CineLarkKit`: 60 tests across 7 suites pass.
  New coverage includes equal/backward/observed HLC time, bootstrap resolution,
  mutation precedence, and idempotent non-destructive merge.
- Unsigned `xcodebuild ... test`: 16 Swift Testing tests across 9 suites and 6
  XCTest cases pass.
- `git diff --check` passes.
- The required signed two-device CloudKit verification was not run.

## Deviations from plan

- Runtime first-install resolution is intentionally not enabled yet. A correct
  offline provisional Profile also needs local provisional favorite, playback,
  snapshot, and future viewing-session storage; publishing an object into the
  current Cloud configuration would allow it to upload before user resolution.
- `DeviceRecord`, `ViewingSession`, and `PlaybackEvent` remain schema contracts,
  not implemented entities. The current manifest therefore does not fabricate
  session count, watch time, or a remote device name.
- The TCA learning document was reviewed. No entry was added because this slice
  established domain/repository invariants and did not expose a new reusable
  TCA-specific boundary beyond existing bootstrap guidance.

## Open questions

- Whether initial Profile manifests can rely on a completed
  `NSPersistentCloudKitContainer` import event or require a small explicit
  CloudKit bootstrap index.
- Retention duration and acknowledgement criteria before merged/tombstoned
  Profile data can be physically collected.
- Compatibility evidence required before removing the transitional UHDNow
  adapter and migrating saved sources to the standard Emby runtime.
