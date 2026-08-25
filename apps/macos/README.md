# CineLark for Mac

Native Swift 6 / SwiftUI client for the observed UHDNow API.

## Current vertical slice

- macOS 26-native Liquid Glass navigation and cinematic TV-first browsing
- username/password and optional TOTP login
- issued-token persistence in Keychain
- hot and Continue Watching shelves
- provider collections and search
- dedicated Movies, TV Series, and Favorites navigation
- release/name/rating/update/asset-update/popularity sorting in both directions
- movie/series details, cast and crew pages, seasons, and episodes
- detail-level last-watched context, one-action resume, and episode progress states
- single-content IINA episode replacement for automatic cross-season continuation
- movie/episode version chooser with expandable codec, color, track, and size metadata
- explicit copy-playback-link, copy-download-link, and browser-download actions
- runtime English/Simplified Chinese interface switching
- native Sparkle update checks with an availability-only sidebar prompt
- keyboard-accessible media-version selection and reduced-motion-aware interactions
- native Icon Composer app icon in `Resources/AppIcon.icon`
- persistent bounded metadata cache with stale outage fallback
- Kingfisher artwork pipeline with bounded memory/disk caches and downsampling
- tokenized playback URL construction through the bundled Rust/IINA bridge
- guided IINA plugin installation and Keychain-provisioned bridge pairing
- post-load resume, transport/state/track telemetry, immediate item activation sync, coalesced progress, and terminal stopped reporting

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

The Cask verifies the versioned DMG by SHA-256 and removes quarantine from the
project-signed app. CineLark uses an existing IINA installation; when IINA is
missing, the playback alert links to its official download. The IINA plugin
still requires explicit approval on first playback. CineLark waits for that
approval and continues the original playback automatically. Existing plugin
updates and repairs run only while IINA is fully stopped; otherwise CineLark
asks the user to quit IINA and retry.

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
not install Cargo or manage a bridge process. Tagged releases are universal and
exported on the maintainer Mac with Xcode Automatic Signing. The local release
scripts verify that the app, bridge, and every Sparkle component share one Team
ID, launch the exact exported app, create the DMG, and sign its appcast with the
Sparkle EdDSA key stored under `com.samsonlab.cinelark` in the maintainer
Keychain. `CURRENT_PROJECT_VERSION` must increase for every tag. The current
Apple Development export is not Developer ID notarized; GitHub Actions only
validates tagged source and does not hold release-signing credentials.

Prepare and publish a release from the maintainer Mac:

```sh
scripts/prepare_macos_release.sh build/release
git tag v<version>
git push origin main v<version>
scripts/publish_macos_release.sh build/release
```

## Security

The app never persists account passwords. Provider tokens are stored in
Keychain, and tokenized playback URLs must not be logged, copied into fixtures,
or included in diagnostics.
