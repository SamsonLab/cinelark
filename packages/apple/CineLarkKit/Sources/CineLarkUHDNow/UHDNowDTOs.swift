import Foundation

struct APIEnvelope<Value: Decodable>: Decodable {
    let ok: Bool
    let data: Value
}

struct BasicResponse: Decodable {
    let ok: Bool
}

struct LoginRequest: Encodable {
    let username: String
    let password: String
    let totpCode: String
}

struct LoginDTO: Decodable {
    let token: String
    let expiresAt: String
}

struct PagedDTO<Item: Decodable>: Decodable {
    let page: Int
    let pageSize: Int
    let total: Int
    let items: [Item]
}

struct GenreDTO: Decodable {
    let id: Int
    let name: String
    let slug: String
}

struct UserStateDTO: Decodable {
    let played: Bool?
    let favorite: Bool?
    let positionTicks: Int64?
    let progressPct: Double?
    let lastPlayedAt: String?
}

struct MediaSummaryDTO: Decodable {
    let id: String
    let type: String
    let title: String
    let originTitle: String?
    let description: String?
    let releaseDate: String?
    let releaseYear: Int?
    let rating: Double?
    let posterPath: String?
    let fanartPath: String?
    let logoPath: String?
    let totalSeasons: Int?
    let hasVersions: Int?
    let assetUpdatedAt: String?
    let genres: [GenreDTO]?
    let userState: UserStateDTO?
    let duration: Double?
}

struct CollectionDTO: Decodable {
    let id: String
    let name: String
    let mediaType: String?
    let ord: Int
    let itemCount: Int
}

struct CollectionsDataDTO: Decodable {
    let items: [CollectionDTO]
}

struct CollectionItemsDTO: Decodable {
    let collection: CollectionDTO
    let page: Int
    let pageSize: Int
    let total: Int
    let items: [MediaSummaryDTO]
}

struct PersonCreditDTO: Decodable {
    let id: String
    let name: String
    let avatarPath: String?
    let character: String?
    let sortOrder: Int?
}

struct PersonDetailDTO: Decodable {
    let id: String
    let name: String
    let avatarPath: String?
    let favorite: Bool?
    let tmdbId: FlexibleString?
    let imdbId: String?
}

struct FavoriteMutationRequest: Encodable {
    let itemId: String
    let itemType: String
}

struct FavoriteMutationResponseDTO: Decodable {
    let favorite: Bool
    let itemId: String
    let itemType: String
}

struct MediaDetailDTO: Decodable {
    let id: String
    let type: String
    let title: String
    let originTitle: String?
    let description: String?
    let releaseDate: String?
    let releaseYear: Int?
    let rating: Double?
    let posterPath: String?
    let fanartPath: String?
    let logoPath: String?
    let duration: Double?
    let totalSeasons: Int?
    let hasVersions: Int?
    let assetUpdatedAt: String?
    let genres: [GenreDTO]?
    let userState: UserStateDTO?
    let tmdbId: FlexibleString?
    let imdbId: String?
    let directors: [PersonCreditDTO]?
    let cast: [PersonCreditDTO]?
}

struct SeasonDTO: Decodable {
    let id: String
    let mediaId: String
    let seasonNumber: Int
    let seasonTitle: String
    let posterPath: String?
    let totalEpisodes: Int
    let userState: UserStateDTO?
}

struct SeasonsDataDTO: Decodable {
    let items: [SeasonDTO]
}

struct EpisodeDTO: Decodable {
    let id: String
    let mediaId: String
    let seasonId: String
    let episodeNumber: Int
    let title: String
    let description: String?
    let airDate: String?
    let thumbPath: String?
    let duration: Double?
    let hasVersions: Int?
    let userState: UserStateDTO?
}

struct AudioTrackDTO: Decodable {
    let index: Int
    let codecName: String?
    let bitRate: Int64?
    let channels: Int?
    let channelLayout: String?
    let sampleRate: String?
    let language: String?
    let title: String?
    let isDefault: Bool?
}

struct SubtitleTrackDTO: Decodable {
    let index: Int
    let codecName: String?
    let language: String?
    let title: String?
    let isDefault: Bool?
}

struct VideoAssetDTO: Decodable {
    let assetId: String
    let mediaId: String
    let episodeId: String?
    let name: String?
    let displayName: String?
    let container: String?
    let duration: Double?
    let fileSize: Int64?
    let bitRate: Int64?
    let width: Int?
    let height: Int?
    let resolution: String?
    let encoding: String?
    let profile: String?
    let videoBitRate: Int64?
    let pixFmt: String?
    let frameRate: String?
    let colorSpace: String?
    let colorTransfer: String?
    let colorPrimaries: String?
    let videoRange: String?
    let audioTracks: [AudioTrackDTO]?
    let subtitleTracks: [SubtitleTrackDTO]?
    let playPath: String
}

struct AssetsDataDTO: Decodable {
    let videos: [VideoAssetDTO]
}

struct DeliveryDomainDTO: Decodable {
    let id: String
    let name: String
    let domain: String
    let normalizedHost: String
    let sortOrder: Int
}

struct ContinueItemDTO: Decodable {
    let itemType: String?
    let itemId: String?
    let mediaId: String?
    let title: String?
    let subtitle: String?
    let posterPath: String?
    let thumbPath: String?
    let duration: Double?
    let userState: UserStateDTO?
}

struct PlaybackGroupDTO: Decodable {
    let mediaId: String?
    let title: String?
    let resume: ContinueItemDTO?
    let nextUp: ContinueItemDTO?
}

struct PlaybackShelvesDTO: Decodable {
    let resume: [PlaybackGroupDTO]
    let nextUp: [PlaybackGroupDTO]
}

struct PlaybackUpdateRequest: Encodable {
    let assetId: String
    let itemId: String
    let itemType: String
    let positionTicks: Int64
}

struct PlaybackUpdateResponseDTO: Decodable {
    let userState: UserStateDTO
}

enum FlexibleString: Decodable {
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .string(String(value))
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a string or integer."
                )
            )
        }
    }

    var value: String {
        switch self {
        case .string(let value): value
        }
    }
}
