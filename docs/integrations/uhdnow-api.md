# Observed UHDNow API

- **Status:** Observed, unofficial, and subject to change
- **Evidence date:** 2026-08-20
- **API origin:** `https://www.uhdnow.com/api/v1`
- **Machine-readable draft:** [`specs/uhdnow/openapi.yaml`](../../specs/uhdnow/openapi.yaml)

This document is a sanitized capability inventory derived from two authenticated
browser captures. It contains no captured values, account data, tokens, or real
media IDs. It is not UHDNow documentation or a compatibility guarantee.

## 1. Common conventions

### Response envelope

Successful JSON responses use:

```json
{
  "ok": true,
  "data": {}
}
```

Observed list endpoints place pagination under `data`:

```json
{
  "ok": true,
  "data": {
    "page": 1,
    "page_size": 20,
    "total": 100,
    "items": []
  }
}
```

Error response shape and rate-limit behavior have not been captured.

### Authentication

`POST /auth/login` accepts:

```json
{
  "username": "<redacted>",
  "password": "<redacted>",
  "totp_code": "<optional-redacted>"
}
```

It returns `data.token` and ISO-like `data.expires_at`. Authenticated browser
requests were observed sending the token directly in the `Authorization` header
without the `Bearer` prefix; an `Authorization` cookie was also present in the
web flow.

CineLark should use the header, store the issued token in Keychain, honor
`expires_at`, and avoid browser-cookie coupling.

### Identifiers and time

- Resource IDs look ULID-shaped in captures but must be treated as opaque
  strings.
- Playback positions use ticks: `1 second = 10,000,000 ticks`.
- Dates/timestamps are strings and require tolerant ISO-8601 parsing.
- `has_versions`, rating, and progress fields were observed as integers; do not
  reinterpret them as booleans without adapter-level normalization.

## 2. Endpoint inventory

All paths below are relative to `/api/v1`.

### Authentication and account

| Method | Path | Capability | Evidence |
| --- | --- | --- | --- |
| `POST` | `/auth/login` | username/password/optional TOTP login | Observed |
| `POST` | `/users/me/logout` | end current session | Observed |
| `GET` | `/users/me` | account identity and TOTP state | Observed |
| `GET` | `/traffic/me` | used and allowed traffic bytes | Observed |
| `GET` | `/subscriptions/me` | plan, expiry, limits, download policy | Observed |
| `GET` | `/subscriptions/domains` | available delivery domains | Observed |
| `GET` | `/subscriptions/domains/{domainID}/resolve` | resolve selected VOD host | Observed |

Account data includes sensitive fields and must never be used as fixtures
without replacing every value.

### Discovery

| Method | Path | Query | Capability |
| --- | --- | --- | --- |
| `GET` | `/stream/library/hot` | `page`, `page_size` | hot media page |
| `GET` | `/stream/library/search` | `q`, `page`, `page_size` | media search |
| `GET` | `/stream/library/collections` | — | ordered collection list |
| `GET` | `/stream/library/collections/{collectionID}/items` | `page`, `page_size`, `sort_by`, `sort_order` | collection media page |

Observed `sort_by` values are `release_date`, `updated_at`,
`asset_updated_at`, `title`, `rating`, and `hot`. Observed `sort_order` values
are `asc` and `desc`. This is an observed set, not a server enum guarantee.

### Movie and TV hierarchy

| Method | Path | Query | Capability |
| --- | --- | --- | --- |
| `GET` | `/stream/movies/{movieID}` | — | movie detail and credits |
| `GET` | `/stream/movies/{movieID}/assets` | — | movie versions and tracks |
| `GET` | `/stream/tv/{seriesID}` | — | series detail and credits |
| `GET` | `/stream/tv/{seriesID}/seasons` | — | seasons |
| `GET` | `/stream/tv/{seriesID}/seasons/{seasonID}/episodes` | `page`, `page_size` | episode page |
| `GET` | `/stream/episodes/{episodeID}/assets` | — | episode versions and tracks |
| `GET` | `/stream/tv/{seriesID}/playback-state` | — | series resume and next-up |
| `GET` | `/stream/me/playback-states` | `page_size` | global resume/next-up shelves |

### People

| Method | Path | Query | Capability |
| --- | --- | --- | --- |
| `GET` | `/stream/library/persons/{personID}` | — | person identity and favorite state |
| `GET` | `/stream/library/persons/{personID}/works` | `page`, `page_size`, `sort_by`, `sort_order` | paginated credits |

### Favorites

| Method | Path | Request | Capability |
| --- | --- | --- | --- |
| `GET` | `/stream/me/favorites` | query: `type`, `page`, `page_size` | favorite media/people |
| `POST` | `/stream/me/favorites` | JSON: `item_id`, `item_type` | add favorite |
| `DELETE` | `/stream/me/favorites/tv/{seriesID}` | — | remove TV favorite |

Observed favorite types are `movie`, `tv`, and `person`. A generalized DELETE
shape is plausible but only the TV path above was captured, so adapters must not
assume other variants without a contract test.

### Playback reporting

| Method | Path | Request | Capability |
| --- | --- | --- | --- |
| `POST` | `/stream/playback/progress` | `PlaybackUpdate` | update active position |
| `POST` | `/stream/playback/stopped` | `PlaybackUpdate` | terminal position update |

Observed request:

```json
{
  "asset_id": "<asset-id>",
  "item_id": "<item-id>",
  "item_type": "episode",
  "position_ticks": 1235000000
}
```

`item_type: episode` is directly observed. Movie reporting must be verified
before relying on its item-type value.

Both endpoints return the resulting `user_state`; the stopped response also
included `last_played_at` in the capture.

## 3. Model inventory

### Library item

List/search/collection items can include:

```text
id, type, title, origin_title, description
release_date, release_year, rating, duration
poster_path, fanart_path, logo_path
 total_seasons, has_versions, asset_updated_at
genres[] { id, name, slug }
user_state { played, favorite?, position_ticks, progress_pct, last_played_at? }
```

`duration` is not present in every list context. `favorite` and
`last_played_at` are context-dependent.

### Movie/series detail

Movie and series details add external IDs and credits:

```text
tmdb_id, imdb_id?, last_air_date?
directors[] { id, name, avatar_path, sort_order }
cast[] { id, name, avatar_path, character, sort_order }
```

Fields may be absent or null; model them as optional.

### Seasons and episodes

```text
Season:
  id, media_id, season_number, season_title, poster_path,
  total_episodes, user_state

Episode:
  id, media_id, season_id, episode_number, title, description,
  air_date, thumb_path, duration, has_versions, user_state
```

### Media assets

Movie and episode asset responses contain:

```text
videos[]:
  asset_id, media_id, episode_id?, name, display_name
  container, duration, file_size, bit_rate
  width, height, resolution, encoding, profile
  video_bit_rate, pix_fmt, frame_rate
  color_space?, color_transfer?, color_primaries?, video_range
  audio_tracks[]
  subtitle_tracks[]
  play_path, download_path
subtitles[]
```

Audio tracks expose `index`, codec/bitrate/channel/sample-rate metadata,
language, title, and `is_default`. Embedded subtitle tracks expose `index`,
`language`, `title`, `codec_name`, and `is_default`.

IINA/mpv remains responsible for actual codec, HDR, audio, and subtitle
handling. CineLark uses this metadata only for version selection and display.

## 4. Playback URL construction

The captured asset endpoint returns relative paths:

```text
/play/video/{assetID}
/download/video/{assetID}
```

A delivery host is obtained from the domain endpoints. The playback URL was
verified in IINA, and the current public web client applies the same token query
to playback and download paths:

```text
{resolvedDomain}/play/video/{assetID}?token={accessToken}
{resolvedDomain}/download/video/{assetID}?token={accessToken}
```

Both URLs are short-lived bearer capabilities:

- construct immediately before playback, copy, or browser download
- never persist or cache them
- expose them to the clipboard or browser only after an explicit user action
- redact their queries before logging
- resolve new URLs after token/session changes

The observed image routes use relative forms such as
`/img/i/poster/{id}`, `/img/i/fanart/{id}`, `/img/i/thumb/{id}`, and
`/img/i/avatar/{id}`.

## 5. Playback-state semantics

Global playback state groups entries under `resume` and `next_up`. A resume
entry can contain:

```text
media_id, title
resume:
  item_type, item_id, media_id, title, subtitle
  poster_path, thumb_path, duration
  user_state { played, position_ticks, progress_pct, last_played_at }
next_up: episode-or-null
```

Series playback state returns `resume` and `next_up`, either of which may be
null. Empty and null are valid states, not decoding failures.

## 6. Adapter requirements

- Isolate every JSON key in internal DTOs.
- Decode unknown/missing fields defensively.
- Map external `movie`, `tv`, `episode`, and `person` strings explicitly.
- Convert ticks with checked arithmetic and clamp positions to duration.
- Keep header, cookie, login, and playback URL values out of diagnostics.
- Retry idempotent GETs only under a bounded policy.
- Do not automatically retry mutations unless their outcome is known or the
  operation is safely idempotent.

## 7. Unknowns requiring contract tests

- Error envelope and HTTP status mapping
- Session refresh behavior versus full reauthentication
- Movie playback-report `item_type`
- DELETE favorite paths for movies and people
- Pagination maximums and rate limits
- Playback token/URL lifetime and domain failover behavior
- External subtitle population and URL semantics
- Completion thresholds used by the service
