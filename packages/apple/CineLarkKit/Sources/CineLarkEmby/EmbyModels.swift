import Foundation

struct PublicSystemInfo: Decodable {
    let id: String
    let serverName: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case serverName = "ServerName"
    }
}

struct AuthenticationResult: Decodable {
    let accessToken: String
    let user: User

    struct User: Decodable {
        let id: String
        let name: String

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
        }
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }
}

struct ItemPageDTO: Decodable {
    let items: [ItemDTO]
    let totalRecordCount: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

struct ItemDTO: Decodable {
    let id: String
    let name: String
    let originalTitle: String?
    let type: String
    let overview: String?
    let genres: [String]?
    let productionYear: Int?
    let communityRating: Double?
    let runTimeTicks: Int64?
    let userData: UserDataDTO?
    let providerIDs: [String: String]?
    let collectionType: String?
    let childCount: Int?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let seriesID: String?
    let seasonID: String?
    let premiereDate: String?
    let mediaSourceCount: Int?
    let people: [PersonDTO]?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?

    struct UserDataDTO: Decodable {
        let isFavorite: Bool?
        let played: Bool?
        let playbackPositionTicks: Int64?
        let lastPlayedDate: String?

        enum CodingKeys: String, CodingKey {
            case isFavorite = "IsFavorite"
            case played = "Played"
            case playbackPositionTicks = "PlaybackPositionTicks"
            case lastPlayedDate = "LastPlayedDate"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case originalTitle = "OriginalTitle"
        case type = "Type"
        case overview = "Overview"
        case genres = "Genres"
        case productionYear = "ProductionYear"
        case communityRating = "CommunityRating"
        case runTimeTicks = "RunTimeTicks"
        case userData = "UserData"
        case providerIDs = "ProviderIds"
        case collectionType = "CollectionType"
        case childCount = "ChildCount"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case seriesID = "SeriesId"
        case seasonID = "SeasonId"
        case premiereDate = "PremiereDate"
        case mediaSourceCount = "MediaSourceCount"
        case people = "People"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
    }
}

struct PersonDTO: Decodable {
    let id: String?
    let name: String
    let role: String?
    let type: String?
    let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case role = "Role"
        case type = "Type"
        case primaryImageTag = "PrimaryImageTag"
    }
}

struct PlaybackInfoDTO: Decodable {
    let mediaSources: [MediaSourceDTO]

    struct MediaSourceDTO: Decodable {
        let id: String?
        let name: String?
        let path: String?
        let container: String?
        let size: Int64?
        let runTimeTicks: Int64?
        let bitRate: Int64?
        let mediaStreams: [MediaStreamDTO]?
        let directStreamURL: String?
        let supportsDirectPlay: Bool?
        let supportsDirectStream: Bool?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case path = "Path"
            case container = "Container"
            case size = "Size"
            case runTimeTicks = "RunTimeTicks"
            case bitRate = "Bitrate"
            case mediaStreams = "MediaStreams"
            case directStreamURL = "DirectStreamUrl"
            case supportsDirectPlay = "SupportsDirectPlay"
            case supportsDirectStream = "SupportsDirectStream"
        }
    }

    struct MediaStreamDTO: Decodable {
        let index: Int?
        let type: String?
        let codec: String?
        let profile: String?
        let bitRate: Int64?
        let channels: Int?
        let channelLayout: String?
        let sampleRate: Int?
        let language: String?
        let title: String?
        let displayTitle: String?
        let isDefault: Bool?
        let width: Int?
        let height: Int?
        let realFrameRate: Double?
        let pixelFormat: String?
        let colorSpace: String?
        let colorTransfer: String?
        let colorPrimaries: String?
        let videoRange: String?

        enum CodingKeys: String, CodingKey {
            case index = "Index"
            case type = "Type"
            case codec = "Codec"
            case profile = "Profile"
            case bitRate = "BitRate"
            case channels = "Channels"
            case channelLayout = "ChannelLayout"
            case sampleRate = "SampleRate"
            case language = "Language"
            case title = "Title"
            case displayTitle = "DisplayTitle"
            case isDefault = "IsDefault"
            case width = "Width"
            case height = "Height"
            case realFrameRate = "RealFrameRate"
            case pixelFormat = "PixelFormat"
            case colorSpace = "ColorSpace"
            case colorTransfer = "ColorTransfer"
            case colorPrimaries = "ColorPrimaries"
            case videoRange = "VideoRange"
        }
    }

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
    }
}
