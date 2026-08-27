# 018 — Emby Metadata Fidelity: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-27 |
| **Primary refs** | [`001-action.md`](001-action.md), [`../../docs/integrations/emby.md`](../../docs/integrations/emby.md) |
| **Related** | [Emby real-contract hardening](../017-emby-real-contract-hardening/000-plan.md), [Viewing insights](../015-viewing-insights/000-plan.md), [`docs/integrations/emby.md`](../../docs/integrations/emby.md), [`docs/product/viewing-insights.md`](../../docs/product/viewing-insights.md) |

## Background

The real Emby response audit confirmed that list, resume, and detail items carry
useful metadata already represented by CineLark domain values but not decoded by
the Emby plugin: `OriginalTitle`, `Genres`, `ChildCount`, and
`UserData.LastPlayedDate`.

Dropping these fields weakens both presentation and the long-term Profile value
proposition. Catalog entries cannot show complete series facts, explicit remote
imports lose the provider's last-played instant, and future local viewing
sessions cannot contribute imported genres to viewing insights.

## Goals

- Decode and normalize original title, genre names, series child count, and
  last-played time from standard Emby item responses.
- Request optional summary fields explicitly on browse, latest, resume, and
  works queries rather than relying on server defaults.
- Give name-only Emby genres deterministic local IDs and slugs without treating
  them as canonical cross-source identity.
- Persist the enriched `MediaSummary` unchanged through the local Catalog.
- Project summary genres into Profile snapshots during explicit remote import,
  preserving offline and future Insights use.
- Prevent a partial remote-import snapshot from erasing richer genre/director/
  cast dimensions already captured from detail or playback.
- Keep Emby playback state isolated from the active CineLark Profile except
  during the existing explicit import operation.
- Present original title, genres, duration, and series count on the detail
  surface when available.
- Preserve episode identity when launching an episode from a series hierarchy.

### Non-goals

- Building a global genre ontology or merging genres across languages/sources.
- Backfilling metadata for existing Profile snapshots without revisiting a
  source item.
- Adding recommendation ranking or persisting derived Insight snapshots.
- Importing provider playback state automatically during ordinary browsing.
- Expanding Emby v1 into music, Live TV, transcoding, or offline download.
- Running write/mutation validation against a real Emby account.

## Design / Approach

### Plugin normalization

`ItemDTO` gains optional fields matching Emby's value shapes. Missing,
malformed, or empty optional metadata does not invalidate an otherwise usable
item.

`Genre.normalized(name:)` owns provider-neutral presentation normalization:

- trim surrounding whitespace;
- derive a locale-stable lowercase slug;
- derive a deterministic 32-bit FNV-1a integer ID from the slug;
- discard empty names;
- deduplicate within an item by normalized slug while preserving provider order.

The derived ID exists only for stable value/UI identity. `ContentKey` and
`MediaLocatorID` remain the only matching evidence and exact source identity.

`LastPlayedDate` is parsed as an ISO-8601 absolute instant, accepting fractional
and whole seconds. It populates `UserPlaybackState.lastPlayedAt`; UTC is an
interchange representation, while UI formatting remains local-time-zone aware.

`ChildCount` maps to `totalSeasons` only for `MediaKind.series`. It is not
reinterpreted for movies or episodes.

### Local-first projection

The data path remains one-way:

```text
Emby response -> MediaSummary -> Local Catalog -> TCA presentation
                                    |
                        explicit remote import only
                                    v
                         ProfileMediaSnapshot
                                    v
                         Viewing Insights input
```

Ordinary library/detail rendering continues to replace Emby `UserData` with the
active Profile's local state. Explicit import may copy `lastPlayedAt` and genre
evidence into Profile records because that action is user-requested and already
idempotently marked.

Profile snapshot genre projection stores name and slug. The integer genre ID is
a deterministic local presentation key, not an asserted Emby genre identifier.

Profile snapshot metadata uses dimension-complete merging: a non-empty incoming
dimension replaces the older value, while an absent or empty incoming dimension
retains the existing value. Absence is not a deletion command because the
current schema has no metadata tombstone. This lets genre-only remote imports
coexist with richer director/cast evidence captured during local playback.

### Presentation

The detail view shows the original title only when it is non-empty and differs
from the display title. Genre names are shown in provider order. The existing
extended facts row exposes duration and series count without adding a new
navigation or settings surface.

Selecting a hierarchy episode emits `MediaKind.episode`, ensuring its durable
viewing facts match the item identity introduced in milestone 017.

### Contract fixtures

Add a compact synthetic item-page fixture modeled after the observed response
shape. It covers fractional/whole-second dates, duplicated/whitespace genre
names, original title, series child count, and a movie child count that must not
be interpreted as seasons. No private response values are copied.

## Alternatives & decisions

- **Store raw provider JSON:** rejected because Catalog and Profile boundaries
  require provider-neutral, versionable values.
- **Use Swift `hashValue` for genre IDs:** rejected because it is intentionally
  unstable between processes and unsuitable for persisted presentation keys.
- **Treat Emby genre names as canonical IDs:** rejected because naming and
  localization differ across servers and future source protocols.
- **Apply `LastPlayedDate` during every browse:** rejected because CineLark
  Profile state is the UI authority; provider state enters only by explicit
  import.
- **Fetch metadata while rendering Insights:** rejected because insights must
  remain local-first, offline-capable, and independent of source availability.

## Amendments

- Updated 2026-08-27: implementation review found that record-level snapshot
  replacement could erase richer contributor metadata during a genre-only
  remote import. The plan now requires dimension-complete metadata merging.
