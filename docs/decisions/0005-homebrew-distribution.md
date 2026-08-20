# ADR 0005: Distribute macOS releases through a project Homebrew tap

- Status: Accepted
- Date: 2026-08-20

## Context

CineLark should be installable by family and early testers without requiring an
Apple Developer Program membership or a local Xcode toolchain. The app contains
a native Swift executable, a universal Rust helper, and an IINA plugin. It also
uses Keychain for provider sessions and bridge pairing.

Apple Developer ID signing and notarization provide the best Gatekeeper
experience, but they require Apple-managed credentials and notarization
infrastructure. A project-controlled Homebrew tap can instead pin a release by
SHA-256 and remove quarantine after installation. This is the model already
used by Tokenscope Remix.

Pure ad-hoc signatures are unsuitable for CineLark updates because their
designated requirement is tied to a changing code-directory hash. That can
invalidate Keychain access expectations after every release.

## Decision

Publish one universal DMG for each tagged macOS release and distribute it from
`SamsonLab/homebrew-cinelark`.

Release automation will:

1. build arm64 and x86_64 app and helper slices;
2. sign nested code and the app with a stable, project-controlled self-signed
   code-signing certificate;
3. verify the universal architectures and sealed bundle;
4. publish the DMG and its SHA-256 digest to GitHub Releases; and
5. update the project Homebrew Cask through a protected tap token.

The Cask depends on the official IINA Cask and removes quarantine recursively
from the installed CineLark bundle. The IINA plugin remains an explicit,
first-use installation so its permissions and Keychain authorization stay
visible to the user.

The signing certificate and tap token are GitHub Actions secrets. They must
never be committed. The signing identity is backed up in the maintainer's
Keychain so it can remain stable across release-infrastructure changes.

## Consequences

- Users can install and upgrade with standard Homebrew commands.
- Releases do not require Apple Developer ID credentials or notarization.
- The stable self-signed identity preserves code-integrity checks and a stable
  designated requirement for Keychain ACLs.
- Gatekeeper does not trust the self-signed identity. Installation depends on a
  third-party Cask step that removes quarantine.
- The Cask is not eligible for the official `homebrew/cask` repository while it
  bypasses Gatekeeper.
- The Cask uses Homebrew's structured `postflight_steps` API rather than a
  legacy arbitrary Ruby flight block. A fully qualified install trusts only
  this Cask under Homebrew's third-party tap trust model.
- SHA-256 pinning detects artifact changes relative to the trusted tap, but it
  is not a substitute for Apple's malware scanning, certificate revocation, or
  notarization service.
