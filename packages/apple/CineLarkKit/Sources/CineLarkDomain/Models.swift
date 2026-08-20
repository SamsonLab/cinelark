import Foundation

public struct ProviderCredentials: Sendable, Equatable {
    public let username: String
    public let password: String
    public let totpCode: String?

    public init(username: String, password: String, totpCode: String?) {
        self.username = username
        self.password = password
        self.totpCode = totpCode
    }
}

public struct ProviderSession: Codable, Sendable, Equatable {
    public let token: String
    public let expiresAt: Date

    public init(token: String, expiresAt: Date) {
        self.token = token
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        expiresAt <= Date()
    }
}

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

public enum MediaKind: String, Sendable, Hashable {
    case movie
    case series
}

public struct UserPlaybackState: Sendable, Hashable {
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

public struct Genre: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let slug: String

    public init(id: Int, name: String, slug: String) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

public struct MediaSummary: Sendable, Hashable, Identifiable {
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
}

public struct MediaCollection: Sendable, Hashable, Identifiable {
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

public struct PersonCredit: Sendable, Hashable, Identifiable {
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

public struct MediaDetail: Sendable, Hashable {
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

public struct Season: Sendable, Hashable, Identifiable {
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

public struct Episode: Sendable, Hashable, Identifiable {
    public let id: String
    public let seriesID: String
    public let seasonID: String
    public let number: Int
    public let title: String
    public let synopsis: String?
    public let airDate: String?
    public let thumbnailURL: URL?
    public let durationSeconds: Double?
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
        self.hasMultipleVersions = hasMultipleVersions
        self.userState = userState
    }
}

public enum PlayableKind: String, Sendable, Hashable {
    case movie
    case episode
}

public struct PlayableItem: Sendable, Hashable {
    public let id: String
    public let kind: PlayableKind

    public init(id: String, kind: PlayableKind) {
        self.id = id
        self.kind = kind
    }
}

public struct AudioTrack: Sendable, Hashable, Identifiable {
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

public struct SubtitleTrack: Sendable, Hashable, Identifiable {
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

public struct MediaAsset: Sendable, Hashable, Identifiable {
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
        playPath: String
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
    }
}

public struct ContinueWatchingItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let item: PlayableItem
    public let mediaID: String
    public let title: String
    public let subtitle: String?
    public let posterURL: URL?
    public let thumbnailURL: URL?
    public let durationSeconds: Double?
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
        self.userState = userState
    }
}

public struct PlaybackShelf: Sendable {
    public let resume: [ContinueWatchingItem]
    public let nextUp: [ContinueWatchingItem]

    public init(resume: [ContinueWatchingItem], nextUp: [ContinueWatchingItem]) {
        self.resume = resume
        self.nextUp = nextUp
    }
}

public struct PlaybackUpdate: Sendable {
    public let item: PlayableItem
    public let assetID: String
    public let positionSeconds: Double

    public init(item: PlayableItem, assetID: String, positionSeconds: Double) {
        self.item = item
        self.assetID = assetID
        self.positionSeconds = max(positionSeconds, 0)
    }
}

public struct PlaybackDescriptor: Sendable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let startPositionSeconds: Double

    public init(id: UUID = UUID(), url: URL, title: String, startPositionSeconds: Double = 0) {
        self.id = id
        self.url = url
        self.title = title
        self.startPositionSeconds = max(startPositionSeconds, 0)
    }
}
