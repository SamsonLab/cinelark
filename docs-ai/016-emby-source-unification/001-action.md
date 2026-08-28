# 016 — Emby Source Unification: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-27 | Made standard Emby the only registered media-source runtime | [`../../docs/interfaces/media-source-platform.md`](../../docs/interfaces/media-source-platform.md) |
| 2026-08-27 | Added explicit reconnect migration for persisted UHDNow plugin identity | [`../../docs/integrations/emby.md`](../../docs/integrations/emby.md) |
| 2026-08-27 | Removed the private UHDNow SwiftPM product and app dependency | [`../../packages/apple/CineLarkKit/Package.swift`](../../packages/apple/CineLarkKit/Package.swift) |
| 2026-08-27 | Archived the observed private API inventory | [`../../docs/integrations/uhdnow-api.md`](../../docs/integrations/uhdnow-api.md) |

## Outcome & current state (as of 2026-08-27)

- The composition root registers only `EmbyPluginFactory`; Settings exposes one
  Emby source type for Emby-compatible subscriptions, including UHDNow.
- Plugin factories may declare legacy plugin IDs and return pure
  `SourceMigrationProposal` values. The registry enforces unique ownership
  across canonical and legacy IDs while listing canonical descriptors only.
- A persisted `com.samsonlab.cinelark.uhdnow` source is retained and shown as
  **Reconnect as Emby** instead of being installed or silently rewritten.
- Reconnect reuses the existing `SourceID`, offers the legacy URL without a
  trailing `/api/v1` as an editable suggestion, and requires normal Emby public
  server verification and authentication.
- The canonical source row replaces the legacy row only after successful local
  persistence. The old Keychain session is removed afterward on a best-effort,
  idempotent path.
- The private `/api/v1` transport, DTOs, plugin factory, runtime adapter, product,
  and tests are absent from production and SwiftPM graphs. Sanitized API evidence
  remains archived under `docs/` and `specs/`.
- CineLark Profile remains the local UI authority. Standard Emby playback
  check-ins and explicit import/optional mirror behavior remain independent.

## Validation

- `swift test --package-path packages/apple/CineLarkKit`: all 58 package tests
  pass after removing the UHDNow target. Coverage includes legacy alias routing,
  collision rejection, URL suggestion, and Source-ID preservation.
- Unsigned `xcodebuild ... test`: 28 Swift Testing tests across 11 suites and 6
  XCTest cases pass. `SourceFeatureTests` verifies restore-to-reconnect state,
  successful canonical persistence and cleanup, and non-destructive validation
  failure.
- `xcodegen generate` completes and the generated Xcode dependency graph has no
  `CineLarkUHDNow` product.
- `git diff --check` passes.

## Deviations from plan

- The observed private OpenAPI draft and integration inventory were retained as
  explicitly archived evidence rather than deleted. They are not linked into
  runtime code.
- The legacy provider/session/cache surface was intentionally deferred from this
  milestone and subsequently removed by
  [020 — Legacy provider retirement](../020-legacy-provider-retirement/001-action.md).

## Open questions

- Do not migrate old private-facade item IDs until a verified mapping proves
  identity equivalence with Emby item IDs.
- No unresolved provider compatibility work remains. New Sources normalize
  through Catalog.

The subscriber-facing standard Emby endpoint and login flow were subsequently
validated read-only. See
[017 — Emby real-contract hardening](../017-emby-real-contract-hardening/001-action.md)
for the resulting episode, pagination, and playback URL corrections.
