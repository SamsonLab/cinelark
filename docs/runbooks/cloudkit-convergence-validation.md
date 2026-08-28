# CloudKit Convergence Validation

- **Scope:** signed development or exported CineLark builds
- **Container:** `iCloud.com.samsonlab.cinelark`
- **Evidence:** redacted schema-v1 audit JSON from each physical Mac
- **Safety:** the harness never signs out of iCloud, disables networking,
  removes the app, deletes stores, or overwrites evidence

## Preconditions

Use two physical Macs signed in to the same test iCloud account. Install the
same exact signed CineLark build on both. Do not use personal viewing history
for release validation. Quit CineLark before every capture.

Verify each copied app before starting:

```sh
scripts/validate_cloudkit_sync.sh preflight /Applications/CineLark.app
```

The command verifies the strict code signature, Team-backed application
identity, CloudKit service, and exact container entitlement. It does not contact
CloudKit or read a Profile store.

## Capture and compare

Capture after Settings reports **Up to Date** and no operation is active:

```sh
scripts/validate_cloudkit_sync.sh capture \
  /Applications/CineLark.app \
  "$PWD/build/cloudkit-validation/device-a.json"
```

Run the equivalent command on device B, then place both files on one Mac and
compare them:

```sh
scripts/validate_cloudkit_sync.sh compare \
  build/cloudkit-validation/device-a.json \
  build/cloudkit-validation/device-b.json
```

The capture contains only sync phase, counts, mutation maxima, Profile
fingerprints, and SHA-256 dataset digests. It contains no Profile names or IDs,
media keys, titles, artwork URLs, device names, provider locators, server
addresses, or credentials. Equal counts alone do not pass; all Profile fact
families and the device-record count must converge.

Never compare a capture taken while the phase is Checking, Synchronizing,
Failed, or Local Only. If an export/import event begins during capture, discard
that evidence file and capture to a new path after the UI settles.

## Scenario matrix

Use a new evidence directory per scenario and retain both precondition and
final captures. The operator performs the physical action; the harness only
captures and compares.

| Scenario | Operator procedure | Required evidence |
| --- | --- | --- |
| Delayed initial import | Create history on A. Install and first-launch on B while A is closed. Confirm B stays in Checking or offers Continue Offline until import evidence exists. Do not choose a destructive merge. | Final A/B digest match; B never promotes a duplicate Profile while import is pending. |
| Offline writes | Disconnect B using macOS controls. Change favorite state and complete playback on B. Reconnect, wait for Up to Date on both. | Offline local state remains visible; final A/B digest match with increased state/session/event counts. |
| Concurrent conflict | Keep both offline. Mutate the same favorite/progress on A and B, recording which mutation occurs last in UTC. Reconnect both. | Final A/B digest match and both present the mutation selected by the monotonic stamp rule. |
| Profile merge | Create separate histories, then choose merge on one device. Wait for both. Repeat the merge intent once if the UI permits. | Final A/B digest match; one visible target Profile; counts do not inflate after the repeated intent. |
| Tombstone | Delete a disposable Profile on A while B is closed. Open B only after A reports Up to Date. | Deleted Profile fingerprint is absent from both final audits and is not republished by B. |
| Reinstall | On B, use a disposable macOS user or a separately archived test environment. Remove and reinstall only through normal Finder/package workflows; do not let scripts delete Application Support. | Fresh B waits for import, then final A/B digest match without a duplicate Profile. |
| Account transition | On B, sign out/in using System Settings. Do not automate credentials. Observe Local Only, then Checking/Up to Date after sign-in. | Local facts remain usable while signed out; final A/B digest match after returning to the original account. |

## Pass criteria

A scenario passes only when:

1. both signed apps report Up to Date with no active operation or failure;
2. `compare` exits successfully for the two final captures;
3. local viewing history remained available through offline/error states;
4. no duplicate Profile, lost tombstone, inflated session/event count, or
   provider credential appeared in the evidence;
5. the operator records app version/build, macOS versions, UTC timestamps, and
   the two immutable audit files outside the repository.

Transport-event success alone is not a pass. If the digests differ, retain both
files, wait for another import/export cycle, and capture to new paths. A stable
mismatch after two settled cycles is a release blocker.
