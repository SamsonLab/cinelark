import Foundation

public struct PageRequest: Sendable, Equatable {
    public let number: Int
    public let size: Int

    public init(number: Int, size: Int) {
        self.number = max(number, 1)
        self.size = max(size, 1)
    }
}

public struct Page<Element: Sendable>: Sendable {
    public let number: Int
    public let size: Int
    public let total: Int
    public let items: [Element]

    public init(number: Int, size: Int, total: Int, items: [Element]) {
        self.number = number
        self.size = size
        self.total = total
        self.items = items
    }
}

extension Page: Codable where Element: Codable {}
extension Page: Equatable where Element: Equatable {}

public enum MediaKind: String, Codable, Sendable, Hashable {
    case movie
    case series
    case episode
}

public struct UserPlaybackState: Codable, Sendable, Hashable {
    public let played: Bool
    public let favorite: Bool?
    public let positionSeconds: Double
    public let progress: Double
    public let lastPlayedAt: Date?

    public init(
        played: Bool,
        favorite: Bool? = nil,
        positionSeconds: Double,
        progress: Double,
        lastPlayedAt: Date? = nil
    ) {
        self.played = played
        self.favorite = favorite
        self.positionSeconds = max(positionSeconds, 0)
        self.progress = min(max(progress, 0), 1)
        self.lastPlayedAt = lastPlayedAt
    }

    public static let empty = UserPlaybackState(
        played: false,
        positionSeconds: 0,
        progress: 0
    )
}

public struct Genre: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let slug: String

    public init(id: Int, name: String, slug: String) {
        self.id = id
        self.name = name
        self.slug = slug
    }

    public static func normalized(name rawName: String) -> Self? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let locale = Locale(identifier: "en_US_POSIX")
        let folded = name
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: locale)
            .lowercased(with: locale)
        let components = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let slug = components.isEmpty ? folded : components.joined(separator: "-")
        guard !slug.isEmpty else { return nil }

        var hash: UInt32 = 2_166_136_261
        for byte in slug.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return Self(id: Int(hash), name: name, slug: slug)
    }
}

public struct MediaSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: MediaKind
    public let title: String
    public let originalTitle: String?
    public let synopsis: String?
    public let releaseYear: Int?
    public let rating: Double?
    public let durationSeconds: Double?
    public let posterURL: URL?
    public let backdropURL: URL?
    public let logoURL: URL?
    public let totalSeasons: Int?
    public let hasMultipleVersions: Bool
    public let genres: [Genre]
    public let userState: UserPlaybackState

    public init(
        id: String,
        kind: MediaKind,
        title: String,
        originalTitle: String? = nil,
        synopsis: String? = nil,
        releaseYear: Int? = nil,
        rating: Double? = nil,
        durationSeconds: Double? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        logoURL: URL? = nil,
        totalSeasons: Int? = nil,
        hasMultipleVersions: Bool = false,
        genres: [Genre] = [],
        userState: UserPlaybackState = .empty
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.originalTitle = originalTitle
        self.synopsis = synopsis
        self.releaseYear = releaseYear
        self.rating = rating
        self.durationSeconds = durationSeconds
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.totalSeasons = totalSeasons
        self.hasMultipleVersions = hasMultipleVersions
        self.genres = genres
        self.userState = userState
    }

    public func replacingUserState(_ userState: UserPlaybackState) -> Self {
        Self(
            id: id,
            kind: kind,
            title: title,
            originalTitle: originalTitle,
            synopsis: synopsis,
            releaseYear: releaseYear,
            rating: rating,
            durationSeconds: durationSeconds,
            posterURL: posterURL,
            backdropURL: backdropURL,
            logoURL: logoURL,
            totalSeasons: totalSeasons,
            hasMultipleVersions: hasMultipleVersions,
            genres: genres,
            userState: userState
        )
    }

    public func replacingID(_ id: String) -> Self {
        Self(
            id: id,
            kind: kind,
            title: title,
            originalTitle: originalTitle,
            synopsis: synopsis,
            releaseYear: releaseYear,
            rating: rating,
            durationSeconds: durationSeconds,
            posterURL: posterURL,
            backdropURL: backdropURL,
            logoURL: logoURL,
            totalSeasons: totalSeasons,
            hasMultipleVersions: hasMultipleVersions,
            genres: genres,
            userState: userState
        )
    }
}

public struct MediaCollection: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let mediaKind: MediaKind?
    public let order: Int
    public let itemCount: Int

    public init(id: String, name: String, mediaKind: MediaKind?, order: Int, itemCount: Int) {
        self.id = id
        self.name = name
        self.mediaKind = mediaKind
        self.order = order
        self.itemCount = itemCount
    }
}

public struct PersonCredit: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let character: String?
    public let avatarURL: URL?
    public let order: Int?

    public init(id: String, name: String, character: String?, avatarURL: URL?, order: Int?) {
        self.id = id
        self.name = name
        self.character = character
        self.avatarURL = avatarURL
        self.order = order
    }
}

public struct PersonDetail: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let avatarURL: URL?
    public let isFavorite: Bool
    public let tmdbID: String?
    public let imdbID: String?

    public init(
        id: String,
        name: String,
        avatarURL: URL? = nil,
        isFavorite: Bool,
        tmdbID: String? = nil,
        imdbID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.isFavorite = isFavorite
        self.tmdbID = tmdbID
        self.imdbID = imdbID
    }
}

public enum FavoriteKind: String, Codable, Sendable, Hashable {
    case movie
    case series
    case person
}

public struct FavoriteTarget: Codable, Sendable, Hashable {
    public let id: String
    public let kind: FavoriteKind

    public init(id: String, kind: FavoriteKind) {
        self.id = id
        self.kind = kind
    }
}

public struct MediaDetail: Codable, Sendable, Hashable {
    public let summary: MediaSummary
    public let directors: [PersonCredit]
    public let cast: [PersonCredit]
    public let tmdbID: String?
    public let imdbID: String?

    public init(
        summary: MediaSummary,
        directors: [PersonCredit],
        cast: [PersonCredit],
        tmdbID: String?,
        imdbID: String?
    ) {
        self.summary = summary
        self.directors = directors
        self.cast = cast
        self.tmdbID = tmdbID
        self.imdbID = imdbID
    }
}

public struct Season: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let seriesID: String
    public let number: Int
    public let title: String
    public let posterURL: URL?
    public let episodeCount: Int
    public let userState: UserPlaybackState

    public init(
        id: String,
        seriesID: String,
        number: Int,
        title: String,
        posterURL: URL?,
        episodeCount: Int,
        userState: UserPlaybackState
    ) {
        self.id = id
        self.seriesID = seriesID
        self.number = number
        self.title = title
        self.posterURL = posterURL
        self.episodeCount = episodeCount
        self.userState = userState
    }
}

public struct Episode: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let seriesID: String
    public let seasonID: String
    public let number: Int
    public let title: String
    public let synopsis: String?
    public let airDate: String?
    public let thumbnailURL: URL?
    public let durationSeconds: Double?
    public let versionCount: Int
    public let hasMultipleVersions: Bool
    public let userState: UserPlaybackState

    public init(
        id: String,
        seriesID: String,
        seasonID: String,
        number: Int,
        title: String,
        synopsis: String?,
        airDate: String?,
        thumbnailURL: URL?,
        durationSeconds: Double?,
        versionCount: Int = 0,
        hasMultipleVersions: Bool,
        userState: UserPlaybackState
    ) {
        self.id = id
        self.seriesID = seriesID
        self.seasonID = seasonID
        self.number = number
        self.title = title
        self.synopsis = synopsis
        self.airDate = airDate
        self.thumbnailURL = thumbnailURL
        self.durationSeconds = durationSeconds
        self.versionCount = max(versionCount, 0)
        self.hasMultipleVersions = hasMultipleVersions
        self.userState = userState
    }

    public func replacingUserState(_ userState: UserPlaybackState) -> Self {
        Self(
            id: id,
            seriesID: seriesID,
            seasonID: seasonID,
            number: number,
            title: title,
            synopsis: synopsis,
            airDate: airDate,
            thumbnailURL: thumbnailURL,
            durationSeconds: durationSeconds,
            versionCount: versionCount,
            hasMultipleVersions: hasMultipleVersions,
            userState: userState
        )
    }
}

public enum PlayableKind: String, Codable, Sendable, Hashable {
    case movie
    case episode
}

public struct PlayableItem: Codable, Sendable, Hashable {
    public let id: String
    public let kind: PlayableKind

    public init(id: String, kind: PlayableKind) {
        self.id = id
        self.kind = kind
    }
}

public struct AudioTrack: Codable, Sendable, Hashable, Identifiable {
    public let index: Int
    public let codec: String?
    public let bitRate: Int64?
    public let channels: Int?
    public let channelLayout: String?
    public let sampleRate: String?
    public let language: String?
    public let title: String?
    public let isDefault: Bool

    public var id: Int { index }

    public init(
        index: Int,
        codec: String?,
        bitRate: Int64?,
        channels: Int?,
        channelLayout: String?,
        sampleRate: String?,
        language: String?,
        title: String?,
        isDefault: Bool
    ) {
        self.index = index
        self.codec = codec
        self.bitRate = bitRate
        self.channels = channels
        self.channelLayout = channelLayout
        self.sampleRate = sampleRate
        self.language = language
        self.title = title
        self.isDefault = isDefault
    }
}

public struct SubtitleTrack: Codable, Sendable, Hashable, Identifiable {
    public let index: Int
    public let codec: String?
    public let language: String?
    public let title: String?
    public let isDefault: Bool

    public var id: Int { index }

    public init(index: Int, codec: String?, language: String?, title: String?, isDefault: Bool) {
        self.index = index
        self.codec = codec
        self.language = language
        self.title = title
        self.isDefault = isDefault
    }
}

public struct MediaAsset: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let mediaID: String
    public let episodeID: String?
    public let name: String?
    public let displayName: String
    public let container: String?
    public let durationSeconds: Double?
    public let fileSize: Int64?
    public let bitRate: Int64?
    public let width: Int?
    public let height: Int?
    public let resolution: String?
    public let encoding: String?
    public let profile: String?
    public let videoBitRate: Int64?
    public let pixelFormat: String?
    public let frameRate: String?
    public let colorSpace: String?
    public let colorTransfer: String?
    public let colorPrimaries: String?
    public let videoRange: String?
    public let audioTracks: [AudioTrack]
    public let subtitleTracks: [SubtitleTrack]
    public let playPath: String
    public let downloadPath: String?

    public init(
        id: String,
        mediaID: String,
        episodeID: String? = nil,
        name: String? = nil,
        displayName: String,
        container: String? = nil,
        durationSeconds: Double? = nil,
        fileSize: Int64? = nil,
        bitRate: Int64? = nil,
        width: Int? = nil,
        height: Int? = nil,
        resolution: String? = nil,
        encoding: String? = nil,
        profile: String? = nil,
        videoBitRate: Int64? = nil,
        pixelFormat: String? = nil,
        frameRate: String? = nil,
        colorSpace: String? = nil,
        colorTransfer: String? = nil,
        colorPrimaries: String? = nil,
        videoRange: String? = nil,
        audioTracks: [AudioTrack] = [],
        subtitleTracks: [SubtitleTrack] = [],
        playPath: String,
        downloadPath: String? = nil
    ) {
        self.id = id
        self.mediaID = mediaID
        self.episodeID = episodeID
        self.name = name
        self.displayName = displayName
        self.container = container
        self.durationSeconds = durationSeconds
        self.fileSize = fileSize
        self.bitRate = bitRate
        self.width = width
        self.height = height
        self.resolution = resolution
        self.encoding = encoding
        self.profile = profile
        self.videoBitRate = videoBitRate
        self.pixelFormat = pixelFormat
        self.frameRate = frameRate
        self.colorSpace = colorSpace
        self.colorTransfer = colorTransfer
        self.colorPrimaries = colorPrimaries
        self.videoRange = videoRange
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.playPath = playPath
        self.downloadPath = downloadPath
    }
}

public struct ContinueWatchingItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let item: PlayableItem
    public let mediaID: String
    public let title: String
    public let subtitle: String?
    public let posterURL: URL?
    public let thumbnailURL: URL?
    public let durationSeconds: Double?
    public let seasonID: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let userState: UserPlaybackState

    public init(
        id: String,
        item: PlayableItem,
        mediaID: String,
        title: String,
        subtitle: String?,
        posterURL: URL?,
        thumbnailURL: URL?,
        durationSeconds: Double?,
        seasonID: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        userState: UserPlaybackState
    ) {
        self.id = id
        self.item = item
        self.mediaID = mediaID
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.thumbnailURL = thumbnailURL
        self.durationSeconds = durationSeconds
        self.seasonID = seasonID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.userState = userState
    }
}

public struct PlaybackShelf: Codable, Sendable {
    public let resume: [ContinueWatchingItem]
    public let nextUp: [ContinueWatchingItem]

    public init(resume: [ContinueWatchingItem], nextUp: [ContinueWatchingItem]) {
        self.resume = resume
        self.nextUp = nextUp
    }
}

public struct SeriesPlaybackState: Codable, Sendable, Hashable {
    public let resume: ContinueWatchingItem?
    public let nextUp: ContinueWatchingItem?

    public init(resume: ContinueWatchingItem?, nextUp: ContinueWatchingItem?) {
        self.resume = resume
        self.nextUp = nextUp
    }

    public var resumableItem: ContinueWatchingItem? {
        guard let resume,
              !resume.userState.played,
              resume.userState.positionSeconds > 0 || resume.userState.progress > 0 else {
            return nil
        }
        return resume
    }

    public var primaryItem: ContinueWatchingItem? {
        resumableItem ?? nextUp
    }
}

public struct PlaybackUpdate: Sendable {
    public let item: PlayableItem
    public let assetID: String
    public let positionSeconds: Double
    public let seriesID: String?

    public init(
        item: PlayableItem,
        assetID: String,
        positionSeconds: Double,
        seriesID: String? = nil
    ) {
        self.item = item
        self.assetID = assetID
        self.positionSeconds = max(positionSeconds, 0)
        self.seriesID = seriesID
    }
}

public struct PlaybackDescriptor: Sendable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let startPositionSeconds: Double
    public let startsInFullscreen: Bool
    public let headers: [String: String]

    public init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        startPositionSeconds: Double = 0,
        startsInFullscreen: Bool = true,
        headers: [String: String] = [:]
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.startPositionSeconds = max(startPositionSeconds, 0)
        self.startsInFullscreen = startsInFullscreen
        self.headers = headers
    }
}
