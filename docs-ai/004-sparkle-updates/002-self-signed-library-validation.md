# 004.002 — Replace self-signed releases with Xcode Automatic Signing

## Context

The first Sparkle-enabled release, `v0.1.3`, passed strict recursive code-signing
verification but terminated in `dyld` before application startup. Both the host
and re-signed Sparkle framework used the same project-controlled self-signed
certificate, yet neither signature contained an Apple Team ID. Hardened
Runtime's library validation therefore rejected the dynamic framework as having
a different team identity.

Static `codesign --verify --deep --strict` validation proves bundle integrity;
it does not prove that dyld's runtime library-validation policy will admit every
embedded dynamic framework.

## Change

- Keep Hardened Runtime library validation enabled. Do not add
  `com.apple.security.cs.disable-library-validation`.
- Move release archive and export to the maintainer Mac and use Xcode Automatic
  Signing with Team `4B8LRMN347`.
- Use Xcode Archive and Export so the host, bridge, Sparkle framework, updater,
  autoupdate executable, and both XPC services are all re-signed with the same
  Team ID.
- Make packaging read-only with respect to signatures and fail on a missing or
  inconsistent Team ID.
- Launch the exact exported application for five seconds before packaging so
  runtime framework admission is verified, not inferred from `codesign` output.
- Keep the Sparkle private EdDSA key in the maintainer Keychain and perform
  appcast generation locally. GitHub Actions retains source and unsigned-build
  validation only.
- Ship the correction as `v0.1.4` with bundle build `5`; do not rewrite the
  already published `v0.1.3` tag.

Xcode Automatic Signing successfully archives and exports the complete bundle
with an Apple Development identity, and every inspected component reports Team
`4B8LRMN347`. The exact exported executable remains alive through the launch
smoke interval without the previous dyld termination.

Automatic Developer ID export is not currently available. Apple's certificate
service returned `403 FORBIDDEN_ERROR` because the selected Team does not have
an eligible Apple Developer Program membership. The interim `debugging` export
is therefore still distributed through the quarantine-removing, SHA-pinned
Homebrew Cask. Once membership is available, the same pipeline must switch to
`developer-id` export and add notarization rather than weakening library
validation.

## Validation

- Xcode Automatic Signing Archive succeeded for arm64 and x86_64.
- Xcode automatic `debugging` export succeeded.
- Strict recursive signature verification passed.
- Host, bridge, Sparkle framework, updater, autoupdate executable, Downloader
  XPC, and Installer XPC all report Team `4B8LRMN347`.
- The exact exported application remained alive for more than five seconds.
- Developer ID export failed only at certificate acquisition because the Team
  lacks an eligible program membership; no Developer ID artifact was published.

## Current state

Implemented in the local release pipeline. `v0.1.4` is the first release
prepared through this path.
