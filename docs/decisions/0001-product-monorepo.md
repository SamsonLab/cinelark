# ADR-0001: Product monorepo with an external playback engine

- **Status:** Accepted
- **Date:** 2026-08-20

## Context

CineLark consists of a macOS media client, a future cross-platform mobile
companion, and a thin
IINA plugin. The app and plugin share a versioned bridge contract and must often
change together. IINA already provides mature mpv-based playback, HDR, track,
and subtitle behavior.

## Decision

1. Keep the Mac app, future Flutter Remote, shared packages, protocol specs, and
   IINA plugin in `SamsonLab/cinelark`.
2. Keep provider APIs behind `MediaLibraryProvider`; UHDNow is the first adapter,
   not part of the product identity.
3. Delegate media mechanics to stock IINA/mpv through a thin provider-neutral
   bridge.
4. Do not fork or patch IINA unless a required capability cannot be delivered
   safely through its public plugin API.
5. Keep any experimental IINA fork outside this product repository and pursue
   an upstreamable change when a patch becomes necessary.

## Consequences

- Bridge schema changes and both implementations can land atomically.
- App and plugin may have independent release tags and CI despite sharing a
  repository.
- The plugin contains no UHDNow account logic and can support future providers.
- IINA API gaps are explicit integration blockers rather than hidden fork-only
  behavior.

## Revisit when

Split the plugin only if it becomes a separately governed, general-purpose
project with an independent release and compatibility policy.
