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
- automatic next-episode playback after natural completion
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

The Cask verifies the versioned DMG by SHA-256 and removes quarantine from the
project-signed app. CineLark uses an existing IINA installation; when IINA is
missing, the playback alert links to its official download. The IINA plugin
still requires explicit approval on first playback.

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
The release workflow also signs the DMG and appcast with Sparkle EdDSA and
publishes both to the matching GitHub Release. `CURRENT_PROJECT_VERSION` must
increase for every tag, and `SPARKLE_PRIVATE_KEY` must remain configured as a
GitHub Actions secret.

## Security

The app never persists account passwords. Provider tokens are stored in
Keychain, and tokenized playback URLs must not be logged, copied into fixtures,
or included in diagnostics.
