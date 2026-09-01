# 025 — Single Personal Profile: Plan

| | |
| --- | --- |
| **Status** | Implemented and verified locally |
| **Anchor date** | 2026-08-28 |
| **Primary refs** | [Action](001-action.md), [CloudKit schema](../../docs/interfaces/profile-cloudkit-schema.md) |
| **Related** | [Viewing identity and sync](../014-viewing-identity-and-sync/000-plan.md), [Profile onboarding and sync health](../021-profile-onboarding-and-sync-health/000-plan.md), [CloudKit schema](../../docs/interfaces/profile-cloudkit-schema.md) |

## Background

CineLark currently models multiple named Profiles per iCloud account, stores a
per-device active Profile selection, and can interrupt bootstrap with a choice
between cloud history, a provisional local Profile, or a separate Profile.
The product now has one personal viewing history per iCloud account. Exposing
multi-Profile creation, switching, and conflict choices adds state and UX cost
without a supported product need.

Removing only the Picker would be unsafe. Existing installations may already
contain random Profile IDs, and multiple devices can create provisional state
before the first CloudKit import. Every device must converge on the same target
identity without using device-local selection as authority.

## Goals

- Define one stable personal `ProfileID` inside each private iCloud container.
- Create new provisional and cloud Profiles with that identity on every device.
- Automatically consolidate legacy cloud Profiles and provisional local facts
  into the stable personal Profile after initial cloud availability is known.
- Preserve version-ordered favorites/playback, immutable sessions/events,
  metadata snapshots, import markers, Source bindings, and local selection.
- Keep the app usable from provisional local state while CloudKit initial import
  or account availability is unresolved.
- Remove Profile creation, switching, and merge-choice actions and UI.
- Present one compact viewing-data summary and one truthful iCloud sync status.
- Retain existing CloudKit transport health and external-change reload behavior.

### Non-goals

- Removing `ProfileID` from persisted facts or changing the CloudKit record
  schema solely to rename Profile concepts.
- Sharing one Profile across different Apple IDs or outside the private iCloud
  database boundary.
- Deleting historical merged Profile records; merge markers remain convergence
  evidence and protect older data.
- Treating Emby user state as the CineLark Profile source of truth.

## Design / Approach

### Stable account-scoped identity

Use a documented constant personal `ProfileID`. The same identifier is safe
across Apple IDs because each account owns an isolated private CloudKit zone.
New provisional state uses the same ID, so concurrent first launches naturally
target one record once their private stores synchronize.

### Automatic legacy consolidation

After CloudKit initial import is available, bootstrap ensures the canonical
Profile exists, merges every visible non-canonical cloud Profile into it, and
then promotes or merges this device's provisional Profile. All operations use
the existing hybrid logical clock and repository merge primitives. The target
is never derived from active device selection, creation time, or display name.

Cloud merge must also migrate local Source bindings and selections. Existing
target bindings win identity fields while mirror intent is preserved if either
binding enabled it. Versioned states retain highest mutation stamps; immutable
facts retain their IDs.

### Local-first bootstrap

Pending initial import does not require a user decision. Bootstrap exposes the
canonical provisional Profile immediately and reports iCloud as checking. When
the import completes, the repository bootstrap invalidation automatically
reloads and consolidates into the same identity.

### UI and feature state

`ProfileBootstrap` and `ProfileFeature.State` expose one optional Profile and
manifest, not arrays. Creation, selection, and resolution-choice actions are
removed. App bootstrap has loading and ready states only; sync health is shown
in Settings and never blocks browsing local history.

Settings presents:

- one personal viewing-data summary;
- one iCloud status label and short explanation;
- last successful sync when known;
- one explicit recheck action.

## Alternatives & decisions

- **Choose the oldest or active legacy Profile:** rejected because concurrent
  devices can observe different subsets or device-local selections.
- **Hide multi-Profile UI but preserve multiple active IDs:** rejected because
  it leaves split history and sync ambiguity in the data model.
- **Wait for iCloud before allowing use:** rejected because local viewing memory
  remains safe and useful while CloudKit is pending or unavailable.
- **Delete legacy records after migration:** rejected because CloudKit deletion
  and old-client compatibility add unnecessary destructive risk.

## Validation

- Pure identity/bootstrap tests prove device-independent canonical selection.
- Repository tests prove legacy and provisional facts merge idempotently without
  losing newer state or Source mirror policy.
- TCA tests prove bootstrap no longer waits for Profile choice and repository
  invalidations still refresh the single active context.
- UI source scans prove create/switch/keep-separate controls are removed.
- Full SwiftPM and unsigned macOS tests, followed by `git diff --check`.

## Amendments

- None.
