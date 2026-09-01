# 026 — Provider Content Restoration: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-28 |
| **Primary refs** | [`001-action.md`](001-action.md) |
| **Related** | [Authenticated artwork delivery](../019-authenticated-artwork-delivery/000-plan.md), [Emby metadata fidelity](../018-emby-metadata-fidelity/000-plan.md), [`docs/integrations/emby.md`](../../docs/integrations/emby.md) |

## Background

The configured remote Emby service returns complete poster URLs and series
metadata, but its image endpoint now redirects from the Emby item path to a
same-origin immutable image path. CineLark rejects every capability-resolved
artwork redirect, so valid metadata renders as placeholders.

Series hierarchy loading also depends only on the list item's initial kind. A
stale or incomplete cached summary can therefore suppress seasons and episodes
even when the authoritative detail response identifies a Series.

## Goals

- Render artwork delivered through safe same-origin redirects without widening
  credential scope.
- Continue rejecting cross-origin, credential-bearing, and unsafe redirects.
- Let the authoritative detail response recover Series hierarchy loading when
  the initial summary kind is stale or unknown.
- Preserve one seasons request when both initial and detailed metadata already
  identify the item as a Series.
- Add deterministic regression coverage for both failures.

### Non-goals

- Allow authenticated cross-origin artwork CDNs.
- Put tokens in image URLs, cache keys, Catalog, or presentation state.
- Change Emby season or episode field mappings without contract evidence.
- Rebuild the media detail information architecture.

## Design / Approach

1. Replace the binary artwork redirect switch with a policy that validates the
   proposed URL and permits only redirects whose origin matches the response
   URL origin. Same-origin redirect chains remain allowed; any origin change or
   unsafe URL terminates the download.
2. Track whether hierarchy loading has been requested in `MediaDetailFeature`.
   Request it immediately for a known Series, or after detail loading when the
   authoritative kind corrects the initial summary.
3. Validate the configured service contract without recording credentials or
   private response bodies. Keep only structural evidence in the action log.

## Alternatives & decisions

- **Keep rejecting all redirects:** rejected because the configured service's
  valid Emby image endpoint now uses a same-origin immutable-image redirect.
- **Follow any redirect and rely on URLSession:** rejected because custom Emby
  authorization headers must never cross an origin boundary.
- **Wait for detail before every hierarchy request:** rejected because it adds
  avoidable latency for correctly typed Series items.
- **Trust only the initial list type:** rejected because cached/provider field
  drift can otherwise erase all season and episode presentation.

## Amendments

- None.
