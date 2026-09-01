# CineLark Product Specification

- **Status:** Draft 0.1
- **Last updated:** 2026-08-28
- **Initial platform:** macOS

## 1. Product statement

CineLark is an Apple-ecosystem personal viewing-memory client. It preserves a
user-owned history across replaceable media sources, turns that history into
period insights and preference dimensions, and plays available media through
IINA/mpv with a TV-first interface.

## 2. Goals

1. Make a Mac connected to a television comfortable to operate from a couch.
2. Provide fast discovery across home sections, collections, search, movies,
   series, seasons, episodes, people, favorites, and continue-watching state.
3. Start or resume the selected media version in IINA with minimal friction.
4. Keep playback progress synchronized with the active provider.
5. Provide a focused cross-platform mobile Remote that can operate the full
   couch workflow without duplicating provider or playback ownership.
6. Work fully without CineLark Remote; the companion is an enhancement, not
   an activation or control dependency.
7. Preserve long-term viewing memory in the user's iCloud private database
   independently from Emby, Jellyfin, Plex, or filesystem account state.
8. Build monthly, quarterly, yearly, and all-time insights plus explainable
   on-device recommendations from durable viewing facts before considering an
   external recommendation service.

## 3. Non-goals for the first release

- Implementing a native decoder or replacing IINA/mpv
- Editing media metadata or administering a media server
- A managed offline-download library, background downloader, or DRM store
- Cross-Apple-ID household sharing, parental controls, or social profiles
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
- content-only library navigation with configuration consolidated in the native
  macOS Settings scene
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

It must not authenticate to a media provider or know provider-specific item models.

### 4.3 CineLark Remote

A Flutter companion for iOS and Android that talks to the Mac app through a
pinned local-network session, never directly to a media provider or IINA plugin.
Its focused scope covers QR pairing, secure remote login, sidebar/directional
navigation, search text entry, and contextual IINA controls including transport,
seek, rate, fullscreen, episode navigation, volume, and audio/subtitle tracks.
The mobile client consumes versioned shared contracts rather than Swift
implementation modules.

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
| Account | Discover or manually configure a standard Emby server and sign in | P0 |
| Account | Persist only issued tokens and metadata in Keychain | P0 |
| Home | Continue Watching, collections, and hot items | P0 |
| Browse | Paginated collection browsing and search | P0 |
| Movie | Detail, cast, versions, favorite state, play/resume | P0 |
| TV | Detail, seasons, episodes, next-up, play/resume | P0 |
| Assets | Show resolution, codec, HDR-relevant color metadata, bitrate, audio, and subtitles | P0 |
| Playback | Open an ephemeral URL with separate authorization headers through IINA Bridge | P0 |
| Playback | Play/pause, seek, stop, duration, position, and state | P0 |
| Playback | Audio and subtitle track inventory/selection | P0 |
| Playback | Detail-level resume and automatic next episode after natural completion | P0 |
| Sync | Periodic progress and terminal stopped reporting | P0 |
| Favorites | Read, add, and remove movie/TV favorites | P1 |
| People | Person detail, credits, and person favorites | P1 |
| Insights | Month, quarter, year, and all-time local viewing summaries | P1 |
| Discovery | Explainable active-Source recommendations computed locally from Profile-owned facts | P1 |
| Remote | QR pairing, remote login, navigation, search text entry, and complete contextual IINA controls on iOS/Android | P1 |

## 7. Reliability and performance requirements

- Show cached structure immediately when safe, then refresh provider data.
- Cancel obsolete image and page requests as focus/navigation changes.
- Deduplicate concurrent requests for the same resource.
- Bound artwork memory and disk caches; never cache playback capability URLs or headers.
- Provider requests are cancellable and use explicit timeouts.
- Progress writes are coalesced; a slow provider must not create an unbounded
  queue.
- The app remains navigable while IINA is absent or the bridge is disconnected.

Initial development budgets use privacy-safe monotonic intervals and distinguish a
target from a critical ceiling. They are regression signals, not shared-CI wall-clock
test gates:

| Interval | Target | Critical ceiling |
| --- | ---: | ---: |
| App bootstrap to restored Profile and Source readiness | 1,500 ms | 4,000 ms |
| Safe cached library page applied to state | 150 ms | 400 ms |
| Provider-refreshed library page applied or failed | 1,500 ms | 5,000 ms |
| Primary media detail applied or failed | 800 ms | 2,500 ms |
| Playback request to matching IINA file load | 3,000 ms | 10,000 ms |
| Authenticated Remote command execution and queued acknowledgement | 100 ms | 300 ms |
| Semantic directional focus mutation | 16.67 ms | 33.34 ms |

Local directional focus mutation targets one 60 Hz display frame. Its interval is
measured on the semantic UI path rather than reducer timing; Instruments remains the
authority for confirming that the corresponding visual frame is presented. Artwork
completion does not define semantic content readiness. Physical-device baselines may
revise these values with a documented measurement sample.

## 8. Security and privacy requirements

- Provider credentials and tokens stay in Keychain.
- Playback URLs are bearer capabilities and are redacted from logs, crash
  diagnostics, recent-item metadata controlled by CineLark, and analytics.
- The IINA bridge requires authenticated local communication.
- The Remote requires explicit pairing and revocation.
- No network capture or real account fixture may enter the repository.

## 9. MVP acceptance criteria

A build is MVP-complete when a fresh install can:

1. Configure a standard Emby source, restore its issued token securely, and reconnect a legacy UHDNow source explicitly when present.
2. Browse home sections and collections entirely with directional controls.
3. Search and open movie and TV detail pages.
4. Select an episode or movie version and choose Resume or Start Over.
5. Launch stock IINA with the CineLark plugin and play the selected media descriptor.
6. Reflect pause, position, duration, end, and close events in the Mac app.
7. Persist local viewing facts and report Started/Progress/Stopped through standard Emby endpoints.
8. Recover gracefully when the provider, IINA, or bridge is unavailable.
9. Pass a repository secret scan with only synthetic fixtures present.

The cross-platform Remote is explicitly not part of the Mac MVP completion, but
is the next focused product milestone. A standalone mobile library client, local
mobile playback, and casting remain outside this Remote milestone.

## 10. Open product decisions

- Minimum IINA version
- Resume-start and watched-completion thresholds
- Default asset selection policy when multiple versions exist
- Distribution/signing strategy for app and plugin
- Bonjour-based endpoint recovery and lock-screen Remote controls
