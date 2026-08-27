# 017 — Emby Real-Contract Hardening: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-27 |
| **Primary refs** | [`001-action.md`](001-action.md), [`../../docs/integrations/emby.md`](../../docs/integrations/emby.md) |
| **Related** | [Media source platform](../011-media-source-platform/000-plan.md), [Emby source unification](../016-emby-source-unification/000-plan.md), [`docs/integrations/emby.md`](../../docs/integrations/emby.md), [`SECURITY.md`](../../SECURITY.md) |

## Background

Read-only validation against a real standards-compatible Emby service exposed
three contract defects that synthetic tests did not cover:

- `/Items/Resume` returns both `Movie` and `Episode`, while the domain mapper
  currently drops episodes;
- offset pagination advances by the number of mapped results instead of the
  number of provider results consumed, which can repeat or stall a cursor;
- `DirectStreamUrl` can be a root-relative URL containing a provider token, but
  the current resolver treats it as a path component and leaks that token into
  the playback descriptor.

The supplied Postman collection and live account are private diagnostic inputs.
They must not become repository fixtures or documentation evidence containing
real account, viewing-history, server, filesystem, or credential data.

## Goals

- Represent Emby episodes as first-class provider-neutral media summaries.
- Keep Emby offset cursors based on raw provider records consumed, independent
  of normalization success.
- Guarantee paginated imports terminate if a provider repeats a cursor.
- Resolve absolute, root-relative, and base-path-relative direct-stream URLs
  without corrupting their path or query.
- Remove credential-bearing query parameters from playback descriptors and
  authenticate playback through `X-Emby-Authorization` only.
- Add small synthetic fixtures shaped after the observed responses and cover
  the regressions deterministically.

### Non-goals

- Committing or replaying private Postman responses or live credentials.
- Exercising favorites, played-state, or playback check-in mutations against a
  live server.
- Adding server transcoding support.
- Completing every optional Emby metadata field mapping in this milestone.
- Exposing episodes as a new top-level library category.

## Design / Approach

### Episode identity

Add `episode` to `MediaKind` and to the Emby capability descriptor. The Emby
normalizer maps `Type == "Episode"` to this value while retaining the exact
episode provider item ID in `MediaLocatorID`.

This preserves the actual playable identity in local profile facts and future
insights. Episodes remain children of series in the UI; the new kind describes
the item, not a new navigation section.

### Offset pagination

Both generic and specialized Emby page loaders calculate the next offset as:

```text
current StartIndex + raw Items.count
```

Normalization may intentionally omit unsupported item types, but that must not
change which remote records have already been consumed. The import collector
also tracks observed cursors and rejects a repeated cursor as an invalid remote
response instead of spinning until cancellation.

### Playback URL boundary

The Emby runtime owns direct-stream URL normalization:

1. resolve an absolute HTTP(S) URL directly;
2. resolve a leading-slash reference against the configured server origin;
3. resolve other relative references against the configured base path;
4. remove fragments and case-insensitive credential query names such as
   `api_key`, `api-key`, `token`, and `x-emby-token`;
5. reject non-HTTP(S), cross-origin, or malformed results before attaching an
   account authorization header;
6. return the normal Emby authorization header separately.

The live service was verified to accept a ranged playback request after its
`api_key` query item was removed, using only `X-Emby-Authorization`. The test
suite will validate the transformation without making live requests.

### Sanitized contract fixtures

`CineLarkEmbyTests` receives resource fixtures with synthetic IDs, titles,
hosts, tokens, and paths only:

- a resume page containing episodes and a movie;
- playback info containing a root-relative direct-stream URL with a fake secret
  and a benign query item.

Tests load these resources through `Bundle.module`. No fixture is copied
verbatim from the private response collection.

## Alternatives & decisions

- **Map Episode as Series:** rejected because it corrupts item identity,
  playback semantics, and viewing-insight classification.
- **Advance by normalized item count:** rejected because normalization and
  provider pagination are independent contracts.
- **Keep `api_key` in the stream URL:** rejected because playback URLs are
  capability-bearing and can escape through logs, history, or player state.
- **Use the private response collection as a fixture:** rejected by repository
  security policy and because broad snapshots are brittle regression tests.

## Amendments

- None.
