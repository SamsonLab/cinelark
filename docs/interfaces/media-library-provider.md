# Media Library Provider Interface

- **Status:** Draft
- **Audience:** domain, provider, and application implementers

This contract isolates CineLark from provider-specific APIs. Names below express
semantics, not a frozen Swift source API.

## 1. Design rules

1. IDs are opaque and scoped to one provider account.
2. Domain models contain no provider DTOs, URLs with embedded credentials, or
   transport headers.
3. All I/O is asynchronous, cancellable, and `Sendable` at the implementation
   boundary.
4. Missing provider capabilities are explicit; callers do not infer support
   from request failures.
5. Playback descriptors are generated just in time and are never persisted.
6. Position values use seconds in the domain; provider-specific units are
   converted only by adapters.

## 2. Capability model

```swift
struct ProviderCapabilities: OptionSet, Sendable {
    static let collections
    static let search
    static let favorites
    static let people
    static let multipleVersions
    static let resume
    static let progressReporting
    static let downloads
}
```

The UHDNow observations support every capability above except downloads, which
is exposed by the API but outside the CineLark MVP.

## 3. Conceptual protocol

```swift
protocol MediaLibraryProvider: Sendable {
    var identity: ProviderIdentity { get }
    var capabilities: ProviderCapabilities { get }

    func restoreSession() async throws -> ProviderSession?
    func signIn(using credentials: ProviderCredentials) async throws -> ProviderSession
    func signOut() async

    func home(page: PageRequest) async throws -> HomeContent
    func collections() async throws -> [MediaCollection]
    func items(in collectionID: CollectionID, page: PageRequest, sort: MediaSort?) async throws -> Page<MediaSummary>
    func search(_ query: String, page: PageRequest) async throws -> Page<MediaSummary>

    func movie(id: MediaID) async throws -> MovieDetail
    func series(id: MediaID) async throws -> SeriesDetail
    func seasons(seriesID: MediaID) async throws -> [Season]
    func episodes(seriesID: MediaID, seasonID: SeasonID, page: PageRequest) async throws -> Page<Episode>

    func person(id: PersonID) async throws -> PersonDetail
    func works(personID: PersonID, page: PageRequest, sort: MediaSort?) async throws -> Page<MediaSummary>

    func favoriteMedia(kind: MediaKind, page: PageRequest) async throws -> Page<MediaSummary>
    func favoritePeople(page: PageRequest) async throws -> Page<PersonDetail>
    func setFavorite(_ favorite: Bool, target: FavoriteTarget) async throws -> FavoriteState

    func playbackState(for item: PlayableID) async throws -> ItemPlaybackState
    func playbackStates(limit: Int) async throws -> PlaybackShelf
    func assets(for item: PlayableID) async throws -> [MediaAsset]
    func makePlaybackDescriptor(assetID: AssetID) async throws -> PlaybackDescriptor
    func makeDownloadURL(assetID: AssetID) async throws -> URL

    func reportProgress(_ update: PlaybackUpdate) async throws -> UserPlaybackState
    func reportStopped(_ update: PlaybackUpdate) async throws -> UserPlaybackState
}
```

Authentication may be split into a separate service during implementation, but
credentials must remain outside presentation and plugin layers.

## 4. Core types

### 4.1 Identity and references

```swift
struct ProviderIdentity: Sendable, Hashable {
    let kind: String
    let accountID: String?
}

struct MediaReference: Sendable, Hashable {
    let provider: ProviderIdentity
    let id: String
    let kind: MediaKind
}

enum MediaKind: String, Sendable {
    case movie
    case series
    case season
    case episode
    case person
}
```

Provider adapters map external values such as UHDNow `tv` to the domain
`series` case.

### 4.2 Summary and detail

`MediaSummary` carries only list/grid data:

- reference, title, original title
- release date/year and rating normalized to a `0...10` scale
- synopsis preview
- poster, fanart, and logo image references
- genres
- duration when applicable
- season/version availability hints
- `UserPlaybackState`

Movie/series details extend the summary with provider IDs, full people credits,
and series metadata. Season and episode types preserve numeric ordering without
assuming IDs are numeric.

### 4.3 Playback state

```swift
struct UserPlaybackState: Sendable, Equatable {
    let played: Bool
    let favorite: Bool?
    let position: Duration
    let progress: Double
    let lastPlayedAt: Date?
}

struct ItemPlaybackState: Sendable, Equatable {
    let resume: ResumeCandidate?
    let nextUp: Episode?
}
```

`progress` is normalized to `0...1`; adapters clamp malformed external values.
A missing resume candidate is distinct from position zero.

### 4.4 Assets and tracks

```swift
struct MediaAsset: Sendable, Hashable {
    let id: AssetID
    let displayName: String
    let container: String?
    let duration: Duration?
    let fileSize: Int64?
    let bitRate: Int64?
    let video: VideoCharacteristics?
    let audioTracks: [AudioTrack]
    let subtitleTracks: [SubtitleTrack]
    let downloadReference: String?
}

struct PlaybackDescriptor: Sendable {
    let playbackID: UUID
    let url: URL
    let expiresAt: Date?
    let title: String
}
```

`PlaybackDescriptor` is a bearer capability. It must not conform to
`Codable`, `Hashable`, `CustomStringConvertible`, or any logging protocol by
default. A custom redacted diagnostic representation is required.

### 4.5 Progress updates

```swift
struct PlaybackUpdate: Sendable {
    let playbackID: UUID
    let item: PlayableID
    let assetID: AssetID
    let position: Duration
}
```

The coordinator owns cadence and retries. Adapters perform unit conversion and
external item-type mapping.

## 5. Pagination and sorting

```swift
struct PageRequest: Sendable, Equatable {
    let number: Int       // one-based at the provider boundary
    let size: Int
}

struct Page<Element: Sendable>: Sendable {
    let number: Int
    let size: Int
    let total: Int
    let items: [Element]
}

enum MediaSortField {
    case releaseDate
    case updatedAt
    case assetUpdatedAt
    case title
    case rating
    case popularity
}
```

Adapters reject non-positive page numbers/sizes before network I/O. A sort mode
not supported by the provider produces an explicit capability/input error.

## 6. Error taxonomy

```swift
enum ProviderError: Error, Sendable {
    case unauthenticated
    case sessionExpired
    case forbidden
    case notFound
    case rateLimited(retryAfter: Duration?)
    case invalidRequest
    case invalidResponse
    case unavailable
    case unsupportedCapability
    case cancelled
}
```

Transport/library errors are retained as private underlying diagnostics after
redaction; UI and domain layers consume only this stable taxonomy.

## 7. Contract tests

Each adapter must pass shared tests for:

- pagination and empty pages
- optional/null fields and unknown enum values
- seconds/unit round trips
- resume and completion boundaries
- multiple media versions and track mapping
- token/session expiration
- redacted request, error, and playback-descriptor diagnostics
- cancellation and stale-response suppression
