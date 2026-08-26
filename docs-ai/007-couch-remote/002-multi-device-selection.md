# 007.002 — Multi-device Selection

## Context

The initial Flutter Remote persisted one `PairedMac` record and automatically
reconnected on launch. That made the first screen unpredictable and prevented a
phone from retaining credentials for more than one CineLark Mac.

## Change

- Secure storage now contains an ordered `paired-macs-v2` collection keyed by
  Mac service ID. A valid `paired-mac-v1` record is migrated on first load.
- Cold launch stops at device selection and does not open a network connection.
- Each item shows the Mac-advertised device name and LAN endpoint. The final
  item always starts QR pairing for a new device.
- Selecting a device creates the sole active Remote session. Leaving the Remote
  returns to selection and closes that session without deleting credentials.
- Forgetting removes only the selected Mac. Revocation and authentication
  failure retain this device-scoped behavior.
- The Mac Remote management sheet registers a presentation-scoped dismissal;
  an authenticated `navigation.back` closes that sheet before falling through
  to normal semantic navigation.

No wire protocol, credential proof, certificate pinning, or Mac authorization
rule changed. The phone still maintains at most one live Mac connection.

## Validation

- `fvm flutter analyze` passed.
- `fvm flutter test` passed all 16 tests, including secure-storage migration,
  selection ordering, non-connecting initialization, and device-scoped
  forgetting.
- `fvm flutter build ios --simulator --no-codesign` produced `Runner.app`.
- `fvm flutter build apk --debug` produced `app-debug.apk`; Flutter emitted a
  future Built-in Kotlin migration warning for `mobile_scanner`.
- The macOS Xcode suite passed all tests with code signing disabled, including
  the presentation dismissal registry tests.

## Deviations from plan

This follow-up was documented after implementation had started. The change was
recognized as an enduring secure-storage and launch-navigation decision during
verification; chronology has not been rewritten as a pre-implementation plan.

## Current state

Device selection is the stable mobile entry point. Endpoint refresh after a
Mac address or port change remains dependent on future Bonjour recovery work.
