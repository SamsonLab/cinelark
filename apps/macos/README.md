# CineLark for Mac

Native Swift 6 / SwiftUI client for the observed UHDNow API.

## Current vertical slice

- username/password and optional TOTP login
- issued-token persistence in Keychain
- hot and Continue Watching shelves
- provider collections and search
- dedicated Movies, TV Series, and Favorites navigation
- release/name/rating/update/asset-update/popularity sorting in both directions
- movie/series details, cast and crew pages, seasons, and episodes
- movie/episode version chooser with expandable codec, color, track, and size metadata
- explicit copy-playback-link, copy-download-link, and browser-download actions
- runtime English/Simplified Chinese interface switching
- native Icon Composer app icon in `Resources/AppIcon.icon`
- persistent bounded metadata cache with stale outage fallback
- Kingfisher artwork pipeline with bounded memory/disk caches and downsampling
- tokenized playback URL construction and direct opening in IINA

Direct IINA launch is a temporary degraded playback adapter. Precise resume,
transport telemetry, and progress reporting require the planned bundled Rust
Bridge Helper and thin IINA plugin.

Metadata is persisted under `Application Support/CineLark/MetadataCache` and is
cleared on account transitions. Artwork uses Kingfisher's separate cache under
the system cache directory. Credentials, provider tokens, and tokenized playback or
download URLs are excluded from both stores.

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
