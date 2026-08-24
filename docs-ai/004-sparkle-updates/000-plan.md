# 004 — Sparkle Updates: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-24 |
| **Primary refs** | [Updater integration](../../apps/macos/Sources/App/SparkleUpdateViews.swift), [release workflow](../../.github/workflows/release.yml), [ADR 0006](../../docs/decisions/0006-sparkle-updates.md) |
| **Related** | [ADR 0005](../../docs/decisions/0005-homebrew-distribution.md), [macOS release workflow](../../.github/workflows/release.yml) |

## Background

CineLark publishes universal, project-signed DMGs through GitHub Releases and a
Homebrew tap. Installed applications cannot currently discover or install a new
release without leaving the app. Sparkle provides a native macOS update flow,
but safely adopting it also requires an authenticated appcast, durable signing
credentials, monotonically increasing bundle versions, and correct signing of
Sparkle's nested helpers.

The project intentionally uses a stable self-signed code-signing identity rather
than Apple Developer ID and notarization. Sparkle's EdDSA verification therefore
becomes the primary cryptographic trust boundary for in-app updates. Losing that
private key would prevent safe key rotation without introducing a separately
trusted release path.

## Goals

- Integrate Sparkle 2.9.2 as an exactly pinned Swift package dependency.
- Use Sparkle's standard updater controller and native update UI.
- Add a conventional `Check for Updates…` application-menu command.
- Show a low-emphasis update action beside the sidebar version label only after
  Sparkle has confirmed that a valid newer version is available.
- Check automatically on Sparkle's user-respecting schedule without forcing a
  network request on every launch.
- Publish a stable HTTPS appcast through GitHub Releases.
- Sign both update archives and the appcast with one EdDSA key whose private
  material never enters version control.
- Preserve the current universal DMG and Homebrew distribution paths.
- Explicitly sign and verify Sparkle's nested updater helpers in the custom
  release packaging workflow.

### Non-goals

- A custom CineLark update interface or sidebar item.
- Silent updates that bypass Sparkle's standard user consent and preferences.
- Delta updates in the initial release pipeline.
- Apple Developer ID signing or notarization.
- Supporting a second update channel or prerelease channel.

## Design / Approach

`CineLarkApp` owns one `SPUStandardUpdaterController`, starts it with the app,
and exposes `SPUUpdater.checkForUpdates()` through a SwiftUI command group after
the application-info command. A retained updater delegate publishes only the
latest valid update's display version. The same updater instance and delegate
state are injected into the view hierarchy so a compact action appears beside
the sidebar version label only while that state is non-empty. Clicking it
triggers the identical standard flow. Sparkle retains responsibility for
scheduling, permission prompts, presentation, download, verification, and
installation.

The generated Info.plist contains the stable feed URL, public EdDSA key,
`SURequireSignedFeed`, and `SUVerifyUpdateBeforeExtraction`. The feed URL uses
GitHub's latest-release asset redirect:

```text
https://github.com/SamsonLab/cinelark/releases/latest/download/appcast.xml
```

Every tagged release generates a single-item appcast whose enclosure points to
the immutable versioned DMG asset. A single latest item is sufficient for every
older CineLark build to discover the newest release; retaining prior items is
not required until delta updates or phased channels are introduced.

Sparkle's private key is generated once in the maintainer's login Keychain. An
exported representation is stored only as the `SPARKLE_PRIVATE_KEY` GitHub
Actions secret for non-interactive release signing. The committed public key is
safe to distribute. The maintainer Keychain and Actions secret are the two
operational copies and must be protected as release credentials.

The release workflow resolves the exact Sparkle artifact, packages the existing
DMG, signs it with Sparkle's update-signing tool, generates and signs the
appcast, uploads both assets, and keeps Homebrew SHA-256 publication unchanged.
The custom bundle signer signs Sparkle's XPC services, updater application,
autoupdate executable, and framework from the innermost code outward before
sealing the host application.

`CURRENT_PROJECT_VERSION`, not `MARKETING_VERSION`, remains Sparkle's ordering
source and must increase on every published tag. Release validation will reject
a non-numeric or non-positive bundle version.

## Alternatives & decisions

| Alternative | Decision |
| --- | --- |
| Add only the framework and defer feed configuration | Rejected because starting an unconfigured updater produces a broken runtime path rather than a usable feature. |
| Build a custom Apple TV-styled updater | Rejected because update trust and lifecycle UI should remain recognizable, native, and owned by Sparkle; CineLark customizes only the entry point. |
| Publish an unsigned appcast | Rejected because a compromised feed could misrepresent update metadata even when the archive itself remains signed. |
| Commit the private EdDSA key or an encrypted key file | Rejected; release credentials belong in Keychain and GitHub Actions secrets, outside repository history. |
| Replace Homebrew with Sparkle | Rejected; Homebrew remains the installation and explicit command-line upgrade path. |
| Enable delta updates immediately | Deferred until two genuine signed releases can validate delta generation and fallback behavior. |

## Amendments

- The sidebar action was explicitly constrained to update-available state. It is
  not a persistent manual-check control; the application menu owns that stable
  entry point.
