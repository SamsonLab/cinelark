# ADR 0011: CineLark Owns Personal Viewing Memory

- **Status:** Accepted
- **Date:** 2026-08-27

## Decision

CineLark's durable user value is a source-independent personal viewing memory.
An iCloud private database is the synchronization scope, not an application
identity. It may contain multiple CineLark Profiles.

Media servers and accounts are replaceable sources. Their playback, favorite,
and watched state remains an independent remote record. CineLark may explicitly
import that state and may report local playback through the provider's standard
client protocol, but provider data never becomes the live UI authority.

## Identity boundaries

- `ClientID`: local installation identity and Emby `DeviceId`; never synced or
  replaced by Profile resolution.
- `DeviceRecordID`: synced presentation/audit record for a known client.
- `ProfileID`: durable owner of viewing history, favorites, ratings, insights,
  and preference projections.
- `SourceID`: configured media source identity. Credentials and connection
  details remain device-local.
- `RemoteUserID`: provider-owned account identity bound to a Source.
- `ContentKey`: optional canonical matching evidence across Sources.
- `MediaLocatorID`: exact provider or filesystem location.

## Synchronization semantics

Viewing sessions and playback events are append-oriented facts. Current
progress, favorites, ratings, and Profile metadata are projections over facts
or explicit mutations. Mutations use a hybrid logical clock; UTC wall time is
retained for analytics and display but is not the sole conflict authority.

Deletion produces a tombstone. Physical cleanup is delayed until retention and
sync safety can be demonstrated. CloudKit server metadata is transport evidence
and does not replace domain merge rules.

## Bootstrap semantics

A fresh installation creates a local `ClientID` and provisional Profile before
network access. It must not publish that Profile until CloudKit is confirmed
empty or the user chooses to keep it separate. Existing cloud Profiles expose a
small manifest so the user can attach, merge, or keep separate histories.

Selecting or merging a Profile changes the local Profile binding. It never
changes the client identity.

## Consequences

- Replacing a media server does not erase CineLark history.
- Multiple Profiles can coexist in one iCloud account without becoming the
  default first-run product surface.
- Signed multi-device testing is a release requirement because CloudKit import
  timing and conflict behavior cannot be proven by in-memory tests.
- Recommendations and period insights can be rebuilt from user-owned viewing
  facts without making a provider account the long-term identity.
