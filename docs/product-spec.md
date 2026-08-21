# CineLark Product Specification

- **Status:** Draft 0.1
- **Last updated:** 2026-08-20
- **Initial platform:** macOS

## 1. Product statement

CineLark is a TV-first client for browsing a personal media library and playing
it through IINA/mpv. It combines an Infuse-like, poster-led interface with
predictable directional navigation and provider-neutral domain boundaries.

## 2. Goals

1. Make a Mac connected to a television comfortable to operate from a couch.
2. Provide fast discovery across home sections, collections, search, movies,
   series, seasons, episodes, people, favorites, and continue-watching state.
3. Start or resume the selected media version in IINA with minimal friction.
4. Keep playback progress synchronized with the active provider.
5. Preserve a clean path to additional providers and a cross-platform mobile
   Remote.
6. Work fully without CineLark Remote; the companion is an enhancement, not
   an activation or control dependency.

## 3. Non-goals for the first release

- Implementing a native decoder or replacing IINA/mpv
- Editing media metadata or administering a media server
- A managed offline-download library, background downloader, or DRM store
- Multi-user profile switching
- A general-purpose IINA library browser inside the plugin
- Matching every web-provider feature or visual detail
- Shipping provider credentials to the plugin or Remote

## 4. Product surfaces

### 4.1 CineLark for Mac

The system coordinator and primary UI. It owns:

- provider authentication and Keychain storage
- provider selection and account state
- library/domain mapping and image loading
- navigation, focus, and selection state
- media-version selection and resume decisions
- bridge session management
- provider progress and stopped-event reporting

### 4.2 CineLark IINA Bridge

A thin plugin that owns only:

- creating or controlling the relevant IINA player
- opening opaque playback URLs
- applying resume position
- exposing playback state and available tracks
- receiving transport commands
- emitting playback and lifecycle events

It must not authenticate to UHDNow or know provider-specific item models.

### 4.3 CineLark Remote

A future Flutter companion for iOS and Android that talks to the Mac app, never
directly to a media provider or IINA plugin. Initial capabilities are
navigation, play/pause, seek, volume, and now-playing state. The mobile client
consumes versioned shared contracts rather than Swift implementation modules.

## 5. Experience principles

### 5.1 TV-first focus

- Every interactive element must be reachable through deterministic
  up/down/left/right movement.
- Focus must remain visible at normal television viewing distance.
- Returning from a detail page restores the previous row, item, and scroll
  position.
- Focus must not jump because an image or page finishes loading.
- Keyboard and remote actions share one semantic command layer.

### 5.2 Poster-led, information on demand

- Home prioritizes Continue Watching, provider-curated collections, and hot
  items.
- Detail pages prioritize artwork, title, year, rating, synopsis, resume/play,
  version choice, and season/episode navigation.
- Technical asset details are available when choosing versions but do not
  dominate the browsing UI.

### 5.3 Playback continuity

- A resumable item offers **Resume** and **Start Over**.
- Resume position is clamped to the media duration and ignored near the start or
  completion threshold.
- CineLark reports progress periodically and sends a terminal stopped event on
  stop, close, replacement, or application termination when possible.
- Provider write failures do not interrupt local playback; they are retried or
  surfaced non-modally.

## 6. MVP functional requirements

Priority meanings: **P0** is required for the first usable release; **P1** may
follow without changing the architecture.

| Area | Requirement | Priority |
| --- | --- | --- |
| Account | Login with username/password and optional TOTP | P0 |
| Account | Persist only issued tokens and metadata in Keychain | P0 |
| Home | Continue Watching, collections, and hot items | P0 |
| Browse | Paginated collection browsing and search | P0 |
| Movie | Detail, cast, versions, favorite state, play/resume | P0 |
| TV | Detail, seasons, episodes, next-up, play/resume | P0 |
| Assets | Show resolution, codec, HDR-relevant color metadata, bitrate, audio, and subtitles | P0 |
| Playback | Open tokenized URL through IINA Bridge | P0 |
| Playback | Play/pause, seek, stop, duration, position, and state | P0 |
| Playback | Audio and subtitle track inventory/selection | P0 |
| Playback | Detail-level resume and automatic next episode after natural completion | P0 |
| Sync | Periodic progress and terminal stopped reporting | P0 |
| Favorites | Read, add, and remove movie/TV favorites | P1 |
| People | Person detail, credits, and person favorites | P1 |
| Remote | Flutter-based iOS/Android navigation and transport controls | P1 |

## 7. Reliability and performance requirements

- Show cached structure immediately when safe, then refresh provider data.
- Cancel obsolete image and page requests as focus/navigation changes.
- Deduplicate concurrent requests for the same resource.
- Bound artwork memory and disk caches; never cache tokenized playback URLs.
- Provider requests are cancellable and use explicit timeouts.
- Progress writes are coalesced; a slow provider must not create an unbounded
  queue.
- The app remains navigable while IINA is absent or the bridge is disconnected.

Numeric launch, focus, and cache budgets remain **Open** until the first
prototype is measurable.

## 8. Security and privacy requirements

- Provider credentials and tokens stay in Keychain.
- Playback URLs are bearer capabilities and are redacted from logs, crash
  diagnostics, recent-item metadata controlled by CineLark, and analytics.
- The IINA bridge requires authenticated local communication.
- The Remote requires explicit pairing and revocation.
- No network capture or real account fixture may enter the repository.

## 9. MVP acceptance criteria

A build is MVP-complete when a fresh install can:

1. Authenticate to UHDNow, restore its issued session securely, and log out.
2. Browse home sections and collections entirely with directional controls.
3. Search and open movie and TV detail pages.
4. Select an episode or movie version and choose Resume or Start Over.
5. Launch stock IINA with the CineLark plugin and play the tokenized URL.
6. Reflect pause, position, duration, end, and close events in the Mac app.
7. Persist progress through the UHDNow progress/stopped endpoints.
8. Recover gracefully when the provider, IINA, or bridge is unavailable.
9. Pass a repository secret scan with only synthetic fixtures present.

The cross-platform Remote is explicitly not part of MVP completion.

## 10. Open product decisions

- Minimum IINA version
- Resume-start and watched-completion thresholds
- Default asset selection policy when multiple versions exist
- Distribution/signing strategy for app and plugin
- Exact Remote scope and discovery mechanism
