# ADR-0007: Export macOS releases locally with Xcode Automatic Signing

- Status: Accepted
- Date: 2026-08-24
- Supersedes: the release-signing portions of [ADR-0005](0005-homebrew-distribution.md) and [ADR-0006](0006-sparkle-updates.md)

## Context

The first Sparkle-enabled release, `v0.1.3`, recursively passed strict
`codesign` verification but terminated in `dyld` before application startup.
The host and embedded Sparkle framework had both been re-signed with the same
self-signed certificate, but self-signed identities do not carry an Apple Team
ID. Hardened Runtime library validation therefore rejected the framework as
belonging to a different team.

Disabling library validation would make the release start, but would weaken a
security boundary to preserve a custom signing path. Xcode's Archive and Export
flow already understands Sparkle's nested updater application, executables, and
XPC services and can sign all of them with one Team ID.

The current Apple Team can create Apple Development certificates through Xcode
Automatic Signing. It is not currently enrolled in an Apple Developer Program
membership eligible for Developer ID distribution, so Xcode cannot obtain a
`Developer ID Application` certificate or notarize the application.

## Decision

Prepare release artifacts on the maintainer Mac with the standard Xcode flow:

1. archive the Release scheme with Automatic Signing and provisioning updates;
2. export the archive with the committed automatic-signing export options;
3. require the host, bridge, Sparkle framework, updater, autoupdate executable,
   and both XPC services to share one non-empty Apple Team ID;
4. perform strict recursive signature, universal-architecture, and exact
   exported-application launch checks before packaging;
5. create the DMG without modifying Xcode's signatures; and
6. generate and verify the Sparkle feed with the private EdDSA key stored in the
   maintainer Keychain.

Tag-triggered GitHub Actions validate tests and an unsigned universal build but
do not sign or publish releases. The maintainer publishes the locally prepared
artifacts and updates the Homebrew Cask only after validation succeeds.

Until the Team gains an eligible Apple Developer Program membership, the export
method is Xcode's `debugging` method and the resulting application uses an
Apple Development identity. The Homebrew Cask continues to pin the DMG by
SHA-256 and remove quarantine. This is an explicit interim distribution model,
not a substitute for Developer ID trust or notarization.

When Developer ID becomes available, change the export method to
`developer-id`, enable notarization and stapling, and remove the Cask quarantine
workaround. The archive, export, nested-Team verification, launch smoke test,
Sparkle EdDSA signing, and local publication boundaries remain unchanged.

## Consequences

- Hardened Runtime library validation remains enabled.
- Every executable embedded by Sparkle is signed by Xcode with the host Team ID.
- Release signing credentials stay in the local Keychain and are never exported
  to GitHub Actions.
- The signed app is launchable after Homebrew removes quarantine, but Gatekeeper
  does not accept the current Apple Development export as a public Developer ID
  distribution.
- Sparkle EdDSA permits the transition from the former code-signing identity
  while preserving archive and feed authentication.
- A release must fail before publication if Automatic Signing, nested Team
  consistency, launch testing, or Sparkle feed verification fails.
