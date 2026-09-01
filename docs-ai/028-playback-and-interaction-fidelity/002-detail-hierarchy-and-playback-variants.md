# 028.002 — Detail Hierarchy and Playback Variants

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-08-28 |
| **Primary refs** | `MediaDetailFeature.swift`, `CatalogMediaDetailView.swift`, `Runtime.swift`, `EmbyService.swift` |
| **Reference behavior** | Pre-TCA `e9ec38f^` detail and playback-options flow |

## Context

The restored detail screen currently resolves playback immediately. It also
loads only the selected season's episodes and discards every Emby media source
after the first direct-playable entry. This obscures two established product
semantics:

- the hero Play action resumes the current movie or the current episode;
- the content below the hero is the explicit movie-version or
  season-to-episode selection hierarchy, with a version chooser before an
  explicitly selected episode starts.

Emby exposes these choices as `PlaybackInfo.MediaSources`. The UI must not own
Emby DTOs or credential-bearing stream descriptors.

## Goals

- Introduce a provider-neutral, metadata-only playback variant contract.
- Preserve automatic primary playback for the hero resume action.
- Restore the pre-TCA playback-options sheet for explicit episode selection.
- Restore inline movie versions below the hero.
- Display concrete version counts on episode rows.
- Keep season selection and its episode list visually hierarchical and
  keyboard navigable.
- Resolve a selected variant to an ephemeral descriptor only after playback is
  confirmed.

## Non-goals

- Do not restore the retired UHDNow provider, observable models, or URL-bearing
  `MediaAsset` ownership.
- Do not persist playback URLs, authorization headers, or provider DTOs in TCA
  state.
- Do not redesign Settings, Profile, Sync, or source setup.
- Do not add transcoding profile selection in this pass.

## Design

### Provider contract

`PlaybackResolutionClient` exposes metadata-only `PlaybackVariant` values and
resolves either its preferred source or an explicitly selected variant ID.
Variant metadata includes display name, container, duration, size, bitrate,
video characteristics, and audio/subtitle tracks. `SourcePlaybackDescriptor`
remains the only URL/header carrier.

### Emby mapping

Decode every `MediaSourceInfo` and its `MediaStreams`. Keep only sources that
support direct play or direct stream. Preserve server ordering and mark the
first supported source as preferred. Resolution validates the requested ID
against a fresh PlaybackInfo response and includes that `MediaSourceId` in the
stream request.

### Detail ownership

`MediaDetailFeature` loads movie variants with detail metadata. Explicit movie
or episode selection produces a presentation context; it does not immediately
start playback. The sheet loads episode variants on demand, allows details to
expand, and delegates a confirmed variant to the root playback feature.

The hero action remains direct: movies resume the preferred source. Series use
provider-neutral `SeriesPlaybackState` so Resume or NextUp can target an episode
outside the currently visible season; the loaded episode list remains the
fallback. The preferred target's season becomes the initial visible season.

### Presentation

Reuse the pre-TCA hierarchy and selection language:

- Movie: hero, inline Versions, cast.
- Series: hero, season strip, selected season's episodes, cast.
- Episode rows show `N versions` when `N > 1` and open the version sheet.
- The sheet preserves hero artwork, version cards, expandable technical
  details, pointer/keyboard handoff, and explicit Play confirmation.

## Verification

- Reducer tests for hero resume, sheet presentation, option loading, and
  selected-variant delegation.
- Emby tests for multi-source metadata mapping and exact source resolution.
- CineLarkKit tests, macOS tests, unsigned app build, and `git diff --check`.

## Alternatives and decisions

- Reusing `MediaAsset` is rejected because it embeds old path/download fields
  and would reintroduce provider-era ownership into the new plugin boundary.
- Resolving all stream URLs during detail loading is rejected because it would
  retain credentials and short-lived URLs in presentation state.
- Automatically choosing the first source for explicit episode selection is
  rejected because it hides the user's version choice.

## Current state

Implemented on 2026-08-28:

- `HierarchyClient.seriesPlayback` restores cross-season Resume/NextUp context;
  Emby maps `Users/{user}/Items/Resume` and `Shows/NextUp` into it.
- `PlaybackResolutionClient` exposes metadata-only variants and exact-ID
  resolution while retaining its unary compatibility entry point.
- movie details show inline versions; series details restore the season strip,
  episode list, version counts, and the pre-play selection sheet.
- primary playback skips the explicit selection sheet and resumes the current
  movie or series episode; an explicitly selected episode requires a version
  confirmation.
- the selected variant ID is carried through TCA navigation into fresh Emby
  PlaybackInfo resolution; URLs and headers never enter detail state.

Validation completed with 72 CineLarkKit tests, 48 macOS reducer/integration
tests, an unsigned macOS app build, and `git diff --check`.
