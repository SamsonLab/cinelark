# CineLark for Mac

Native Swift 6 / SwiftUI client for the observed UHDNow API.

## Current vertical slice

- username/password and optional TOTP login
- issued-token persistence in Keychain
- hot and Continue Watching shelves
- provider collections and search
- movie/series details, cast, seasons, and episodes
- media-version and embedded-track metadata
- tokenized playback URL construction and direct opening in IINA

Direct IINA launch is a temporary degraded playback adapter. Precise resume,
transport telemetry, and progress reporting require the planned bundled Rust
Bridge Helper and thin IINA plugin.

## Open and build

```sh
open apps/macos/CineLark.xcodeproj
```

Or build without signing:

```sh
xcodebuild \
  -project apps/macos/CineLark.xcodeproj \
  -scheme CineLark \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run package tests:

```sh
swift test --package-path packages/apple/CineLarkKit
```

`project.yml` is the source definition for XcodeGen; the generated Xcode project
is committed so contributors do not need XcodeGen merely to build the app.

## Security

The app never persists account passwords. Provider tokens are stored in
Keychain, and tokenized playback URLs must not be logged, copied into fixtures,
or included in diagnostics.
