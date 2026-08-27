# 016 — Emby Source Unification: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-27 |
| **Primary refs** | [`001-action.md`](001-action.md), [`../../docs/integrations/emby.md`](../../docs/integrations/emby.md) |
| **Related** | [`../011-media-source-platform/000-plan.md`](../011-media-source-platform/000-plan.md), [`../014-viewing-identity-and-sync/000-plan.md`](../014-viewing-identity-and-sync/000-plan.md), [`../../docs/integrations/emby.md`](../../docs/integrations/emby.md), [`../../docs/interfaces/profile-cloudkit-schema.md`](../../docs/interfaces/profile-cloudkit-schema.md) |

## Background

CineLark currently registers standard Emby and a separate user-visible UHDNow
media-source plugin. The UHDNow target calls an observed private `/api/v1`
surface with its own authentication, pagination, favorites, playback URLs, and
progress protocol. That duplicates the source type, conflicts with the product
decision that UHDNow is an Emby subscription, and creates a second remote-state
contract outside standard Emby behavior.

The desired boundary is one Emby plugin. CineLark Profile facts remain the local
UI truth while the connected Emby user continues to receive standard Emby
Started/Progress/Stopped and optional explicit import/mirror operations.

## Goals

- Register and display only the canonical Emby media-source plugin.
- Route new UHDNow connections through the implemented standard Emby API.
- Remove the UHDNow private transport, DTO, runtime adapter, SwiftPM product,
  production dependency, and conformance tests from the app build.
- Recognize persisted sources with legacy plugin ID
  `com.samsonlab.cinelark.uhdnow` and offer an explicit reconnect migration.
- Preserve the legacy `SourceID` during migration so Profile bindings, Catalog
  isolation, active-selection identity, and viewing-fact namespaces are not
  discarded.
- Verify the canonical Emby server URL and authenticate before replacing the
  persisted source row. Never reinterpret a private UHDNow token as an Emby
  access token.
- Remove the legacy Keychain credential only after canonical source persistence
  succeeds.
- Keep the observed UHDNow API specification as archived research evidence,
  clearly separated from current runtime behavior.

### Non-goals

- Calling or emulating any UHDNow-private `/api/v1` endpoint.
- Automatically discovering the subscriber's Emby URL from private account
  data or guessing credentials.
- Remapping provider item IDs when the private facade and Emby server use
  different identifiers.
- Importing remote state implicitly during migration.
- Changing CineLark Profile ownership, mirror rules, or CloudKit schema.
- Removing the legacy `MediaLibraryProvider` cache adapter in this milestone;
  it remains isolated below the current cache-compatibility boundary.

## Design / Approach

1. Extend `MediaSourcePluginFactory` with declared legacy plugin IDs and a pure
   migration-proposal hook. `PluginRegistry` enforces unique canonical/legacy
   ownership and exposes only canonical descriptors.
2. A `SourceMigrationProposal` contains the original `SourceID`, legacy plugin
   ID, canonical plugin ID, suggested base URL, and display name. It contains no
   credentials and does not install a runtime.
3. `EmbyPluginFactory` owns the old UHDNow plugin ID as a migration alias. Its
   proposal strips a trailing `/api/v1` only as an editable URL suggestion;
   `System/Info/Public` remains the authoritative verification step.
4. Source restoration asks the platform for a migration proposal before
   installation. Legacy sources remain visible but uninstalled and are exposed
   as reconnect-required state rather than normalized silently.
5. The reconnect setup reuses the legacy `SourceID`, lets the user correct the
   server URL, performs normal Emby validation and authentication, then upserts
   the canonical source configuration under the same ID.
6. After repository persistence succeeds, a composition-root cleanup closure
   removes the old UHDNow Keychain session. Cleanup is best-effort and cannot
   roll back a successfully persisted canonical source.
7. Existing Profile bindings remain unchanged. App bootstrap may clear an
   active source that is not installed; successful reconnect selects the same
   source ID again through the existing delegate path.
8. Remove `CineLarkUHDNow` from SwiftPM and the Xcode project. Current docs name
   standard Emby as the only runtime and mark the private API document archived.

## Alternatives & decisions

- Keeping a hidden UHDNow compatibility runtime was rejected because it would
  continue using private endpoints and preserve the duplicated state protocol
  behind a different label.
- Automatically rewriting the legacy source to Emby at bootstrap was rejected:
  the stored URL may point at the private facade, its token is not an Emby
  token, and `remoteUserID` may be absent.
- Allocating a new Source ID during reconnect was rejected because it would
  unnecessarily sever local Profile and Catalog identity even when provider
  item IDs remain stable.
- Deleting legacy sources during bootstrap was rejected because reconnect must
  be recoverable and user-controlled.
- Migrating private provider item IDs is deferred. Without verified mapping
  evidence, a guessed merge could attach history to the wrong content.

## Validation

- Plugin registry tests cover canonical descriptor listing, legacy alias
  uniqueness, and migration proposal routing.
- Emby tests cover canonical migration identity, Source-ID preservation, and
  editable `/api/v1` suffix removal.
- TCA `TestStore` tests cover restore-to-reconnect state, preserved Source ID,
  successful canonical save, credential cleanup, and failed validation without
  destructive mutation.
- Full SwiftPM and unsigned macOS test suites pass after the UHDNow target is
  removed.
- `git diff --check` passes and the generated Xcode project contains no
  `CineLarkUHDNow` product reference.

## Amendments
