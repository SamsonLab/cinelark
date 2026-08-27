# 014.003 — Provisional Profile Bootstrap Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-27 | Added Local-store provisional Profile graph and storage-aware state routing | [`002-provisional-profile-bootstrap.md`](002-provisional-profile-bootstrap.md) |
| 2026-08-27 | Added CloudKit account/import readiness and bootstrap invalidations | [`../../docs/interfaces/profile-cloudkit-schema.md`](../../docs/interfaces/profile-cloudkit-schema.md) |
| 2026-08-27 | Added TCA readiness barrier and root Profile-resolution surface | [`../010-tca-application-architecture/TCA-learn.md`](../010-tca-application-architecture/TCA-learn.md#l014--application-readiness-is-a-semantic-parent-owned-barrier) |

## Outcome & current state (as of 2026-08-27)

- A fresh installation creates `Personal` as a provisional Local-store Profile.
  Favorite, playback, snapshot, and explicit remote-import writes route to
  Local entities while that Profile remains provisional.
- Cloud readiness requires an available iCloud account and either a completed
  successful `NSPersistentCloudKitContainer` import event or an already visible
  Cloud Profile. Account changes and completed imports invalidate bootstrap
  through the repository change stream.
- A confirmed empty Cloud store promotes the provisional graph. Promotion
  writes Profile facts and import markers to the Cloud configuration before
  deleting Local records, and rerunning the operation is safe.
- Existing Cloud Profiles produce an explicit resolution state. Empty local
  state can attach to a Cloud Profile; meaningful local state can merge into a
  selected target; keep-separate promotes it as an additional Cloud Profile.
- Provisional merge preserves original mutation stamps, uses a durable merge
  operation marker, migrates Local Profile/Source bindings and selections, and
  never publishes the provisional source Profile.
- `AppFeature` no longer marks bootstrap ready from `appeared`. Library appears
  only after Profile resolution and account-bound Source restoration. The root
  choice surface shows recent activity, last device identifier, and available
  title/session/favorite/watch-time projections.
- Additional Profile creation is rejected while unresolved provisional state
  exists, avoiding accidental Cloud-store publication during offline bootstrap.

## Validation

- `swift test --package-path packages/apple/CineLarkKit`: 62 tests across 7
  suites pass. New repository coverage proves Local routing, idempotent
  promotion, idempotent provisional merge, and source Profile non-publication.
- Unsigned `xcodebuild ... test` passes all 25 macOS tests, including the new
  `ProfileFeatureTests.profileResolutionChoice` and
  `AppFeatureTests.bootstrapWaitsForProfileResolution` TestStore cases, plus
  repository-invalidation coalescing during active bootstrap.
- Unsigned macOS application build passes.
- `git diff --check` passes for the milestone changes.
- Signed two-device CloudKit verification was not run and remains a release
  gate.

## Deviations from plan

- `DeviceRecord`, `ViewingSession`, and append-only `PlaybackEvent` remain
  future entities. Current manifest session count and watch time are projections
  over `PlaybackState`; the displayed last device is the mutation author ID,
  not yet a friendly synced device name.
- Cloud readiness accepts an existing visible Cloud Profile as equivalent
  evidence when historical import events are unavailable after migration. A
  fresh empty store still requires the successful import event before promotion.
- The attach command is intentionally limited to empty provisional state.
  Meaningful local state must be merged or kept separate.

## Follow-up

- Add Cloud `DeviceRecord`, durable `ViewingSession`, and append-only playback
  facts so Profile manifests and future insights are rebuildable.
- Run signed two-device scenarios for delayed import, offline writes, merge,
  tombstones, reinstall, and iCloud account transitions.
- Add a user-facing local-only/synchronizing status in Settings when device and
  session entities are introduced.
