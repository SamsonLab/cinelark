# ADR-0006: Deliver in-app updates with Sparkle

- Status: Accepted
- Date: 2026-08-24

## Context

CineLark publishes universal, project-signed DMGs through GitHub Releases and a
Homebrew tap. Homebrew remains an appropriate installation and explicit upgrade
path, but an installed application should also be able to discover and install
new versions without leaving the app.

The project does not currently use Apple Developer ID signing or notarization.
Its stable self-signed code identity preserves a consistent designated
requirement, but does not authenticate downloaded update archives independently
of the distribution channel.

## Decision

Integrate Sparkle 2 as an exactly pinned Swift package and use
`SPUStandardUpdaterController` for scheduling, user consent, update presentation,
download, verification, and installation.

The application provides two entry points:

1. a conventional `Check for Updates…` application-menu command that remains
   available whenever Sparkle can perform a check; and
2. a compact action beside the sidebar version label that appears only after
   Sparkle has confirmed a valid newer version.

Tagged releases publish `appcast.xml` beside the versioned universal DMG. The
feed is served through GitHub's latest-release asset redirect, while each
enclosure points to an immutable versioned release URL. Both the archive and the
feed are authenticated with Sparkle EdDSA signatures. The public key is embedded
in the application; private key material exists only in the maintainer Keychain
and the `SPARKLE_PRIVATE_KEY` GitHub Actions secret.

`CURRENT_PROJECT_VERSION` is the update ordering value and must be a positive,
monotonically increasing integer. `MARKETING_VERSION` remains the user-facing
release version. The custom release packager signs Sparkle's nested XPC services,
updater application, autoupdate executable, and framework before sealing the host
application.

The first iteration retains only the latest feed item and does not generate
delta updates or prerelease channels.

## Consequences

- Installed builds gain Sparkle's standard native update experience without a
  parallel custom installer lifecycle.
- The sidebar stays visually quiet when the application is current; checking
  remains discoverable through the application menu.
- Homebrew remains supported and continues to pin the release artifact by
  SHA-256.
- The EdDSA private key becomes a critical release credential. Losing every copy
  prevents existing installations from trusting a replacement key without a
  separately trusted migration release.
- Every published release must increase `CURRENT_PROJECT_VERSION`; changing only
  `MARKETING_VERSION` is insufficient.
- The release workflow must publish the DMG and signed appcast atomically enough
  that the latest-release redirect never advertises an incomplete release.
- Delta updates and multiple channels require revisiting feed retention and
  generation policy.
