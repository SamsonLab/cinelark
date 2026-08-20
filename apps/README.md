# Applications

Planned applications:

- `macos/` — CineLark for Mac, implemented with Swift 6 and SwiftUI first;
  AppKit is used only behind focused adapters.
- `remote/` — future CineLark Remote, implemented with Flutter/Dart for iOS and
  Android.

The Mac app remains the primary coordinator and must be fully usable without
the Remote. The mobile app consumes shared wire contracts; it does not import
provider models or own provider credentials.
