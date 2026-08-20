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
- keyboard-accessible media-version selection and reduced-motion-aware interactions
- native Icon Composer app icon in `Resources/AppIcon.icon`
- persistent bounded metadata cache with stale outage fallback
- Kingfisher artwork pipeline with bounded memory/disk caches and downsampling
- tokenized playback URL construction through the bundled Rust/IINA bridge
- guided IINA plugin installation and Keychain-provisioned bridge pairing
- post-load resume, transport/state/track telemetry, coalesced progress, and terminal stopped reporting

The direct IINA launcher remains available only as a degraded adapter. The
composition root uses the managed bridge path by default.

Metadata is persisted under `Application Support/CineLark/MetadataCache` and is
cleared on account transitions. Artwork uses Kingfisher's separate cache under
the system cache directory. Credentials, provider tokens, and tokenized playback or
download URLs are excluded from both stores.

## Install

```sh
brew install --cask samsonlab/cinelark/cinelark
```

The Cask installs IINA, verifies the versioned DMG by SHA-256, and removes
quarantine from the project-signed app. The IINA plugin still requires explicit
approval on first playback.

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
is committed so contributors do not need XcodeGen merely to build the app. App
builds compile and embed the helper with the pinned Rust toolchain; end users do
not install Cargo or manage a bridge process. Tagged releases are universal,
self-signed with a stable project identity, and intentionally not Apple-notarized.

## Security

The app never persists account passwords. Provider tokens are stored in
Keychain, and tokenized playback URLs must not be logged, copied into fixtures,
or included in diagnostics.
