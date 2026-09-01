import Foundation
import CineLarkDomain
import CineLarkPluginAPI

actor EmbyService {
    static let summaryFields = [
        "Overview",
        "ProviderIds",
        "UserData",
        "RunTimeTicks",
        "OriginalTitle",
        "Genres"
    ]

    let configuration: SourceConfiguration
    let device: EmbyDeviceIdentity
    let http: EmbyHTTPClient
    let tokenVault: EmbyTokenVault
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    init(
        configuration: SourceConfiguration,
        device: EmbyDeviceIdentity,
        http: EmbyHTTPClient,
        tokenVault: EmbyTokenVault
    ) {
        self.configuration = configuration
        self.device = device
        self.http = http
        self.tokenVault = tokenVault
    }

    func authenticate(_ credentials: SourceCredentials) async throws -> AuthenticatedSource {
        guard let username = credentials.username, let password = credentials.password else {
            throw MediaSourceFailure.unauthorized
        }
        let body = try encoder.encode(["Username": username, "Pw": password])
        let request = try builder.request(
            path: "Users/AuthenticateByName",
            method: "POST",
            body: body
        )
        let result: AuthenticationResult = try await response(for: request)
        try await tokenVault.save(result.accessToken, configuration.sourceID)
        let authenticatedConfiguration = SourceConfiguration(
            sourceID: configuration.sourceID,
            baseURL: configuration.baseURL,
            serverIdentity: configuration.serverIdentity,
            displayName: configuration.displayName,
            remoteUserID: result.user.id
        )
        return AuthenticatedSource(
            configuration: authenticatedConfiguration,
            token: result.accessToken
        )
    }

    var builder: EmbyRequestBuilder {
        EmbyRequestBuilder(baseURL: configuration.baseURL, device: device)
    }

    func requiredToken() async throws -> String {
        guard let token = try await tokenVault.load(configuration.sourceID), !token.isEmpty else {
            throw MediaSourceFailure.unauthorized
        }
        return token
    }

    func response<Value: Decodable>(for request: URLRequest) async throws -> Value {
        let response: HTTPResponse
        do {
            response = try await http.send(request)
            try EmbyResponseValidator.validate(response.response)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as MediaSourceFailure {
            throw failure
        } catch {
            throw MediaSourceFailure.transport("Network request failed")
        }
        do {
            return try decoder.decode(Value.self, from: response.data)
        } catch {
            throw MediaSourceFailure.invalidResponse
        }
    }

    func sendMutation(_ request: URLRequest) async throws {
        do {
            let response = try await http.send(request)
            try EmbyResponseValidator.validate(response.response)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as MediaSourceFailure {
            throw failure
        } catch {
            throw MediaSourceFailure.transport("Network request failed")
        }
    }

    func item(id: String) async throws -> ItemDTO {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let request = try builder.request(
            path: "Users/\(userID)/Items/\(id)",
            query: [URLQueryItem(
                name: "Fields",
                value: (Self.summaryFields + ["People"]).joined(separator: ",")
            )],
            token: token
        )
        return try await response(for: request)
    }

    func specialPage(
        pathSuffix: String,
        query: MediaQuery,
        additional: [URLQueryItem] = []
    ) async throws -> MediaPage {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let offset = query.cursor.flatMap { Int($0.rawValue) } ?? 0
        var items = [
            URLQueryItem(name: "StartIndex", value: String(offset)),
            URLQueryItem(name: "Limit", value: String(query.limit)),
            URLQueryItem(
                name: "Fields",
                value: (Self.summaryFields + ["People"]).joined(separator: ",")
            )
        ] + additional
        if !query.kinds.isEmpty {
            items.append(URLQueryItem(
                name: "IncludeItemTypes",
                value: query.kinds.map(Self.embyType).sorted().joined(separator: ",")
            ))
        }
        let request = try builder.request(
            path: "Users/\(userID)/\(pathSuffix)",
            query: items,
            token: token
        )
        let page: ItemPageDTO = try await response(for: request)
        let located = page.items.compactMap(map)
        return MediaPage(
            items: located,
            nextCursor: try Self.nextCursor(
                offset: offset,
                consumedCount: page.items.count,
                total: page.totalRecordCount
            ),
            total: page.totalRecordCount
        )
    }

    func collectPages(
        initial: MediaQuery,
        fetch: (MediaQuery) async throws -> MediaPage
    ) async throws -> [LocatedMediaItem] {
        var query = initial
        var result: [LocatedMediaItem] = []
        var observedCursors = Set<MediaCursor>()
        if let cursor = initial.cursor {
            observedCursors.insert(cursor)
        }
        while true {
            try Task.checkCancellation()
            let page = try await fetch(query)
            result.append(contentsOf: page.items)
            guard let cursor = page.nextCursor else { break }
            guard observedCursors.insert(cursor).inserted else {
                throw MediaSourceFailure.invalidResponse
            }
            query = MediaQuery(
                scope: query.scope,
                parent: query.parent,
                kinds: query.kinds,
                filters: query.filters,
                sort: query.sort,
                cursor: cursor,
                limit: query.limit
            )
        }
        return result
    }

    struct DirectStreamTarget {
        let url: URL
        let authorizationToken: String?
    }

    func canonicalStreamURL(
        locator: MediaLocatorID,
        mediaSourceID: String?,
        token: String
    ) throws -> URL {
        try builder.request(
            path: "Videos/\(locator.providerItemID)/stream",
            query: [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "MediaSourceId", value: mediaSourceID)
            ],
            token: token
        ).url!
    }

    func directStreamTarget(from reference: String) throws -> DirectStreamTarget {
        guard var baseComponents = URLComponents(
            url: configuration.baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw MediaSourceFailure.invalidResponse
        }
        baseComponents.query = nil
        baseComponents.fragment = nil
        baseComponents.user = nil
        baseComponents.password = nil
        if !baseComponents.percentEncodedPath.hasSuffix("/") {
            baseComponents.percentEncodedPath += "/"
        }
        guard
            let resolutionBaseURL = baseComponents.url,
            let resolvedURL = URL(string: reference, relativeTo: resolutionBaseURL)?.absoluteURL,
            var resolvedComponents = URLComponents(
                url: resolvedURL,
                resolvingAgainstBaseURL: false
            ),
            Self.isHTTPOrigin(resolvedComponents),
            Self.isSameOrigin(resolvedComponents, baseComponents)
        else {
            throw MediaSourceFailure.invalidResponse
        }

        resolvedComponents.user = nil
        resolvedComponents.password = nil
        resolvedComponents.fragment = nil
        let authorizationToken = resolvedComponents.queryItems?.first(where: {
            $0.name.caseInsensitiveCompare("token") == .orderedSame &&
                $0.value?.isEmpty == false
        })?.value
        if let authorizationToken,
           authorizationToken.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "," }) {
            throw MediaSourceFailure.invalidResponse
        }
        guard let validatedURL = resolvedComponents.url else {
            throw MediaSourceFailure.invalidResponse
        }
        return DirectStreamTarget(
            url: validatedURL,
            authorizationToken: authorizationToken
        )
    }

    func map(_ item: ItemDTO) -> LocatedMediaItem? {
        guard let kind = Self.mediaKind(item.type) else { return nil }
        let duration = item.runTimeTicks.map { Double($0) / 10_000_000 }
        let summary = MediaSummary(
            id: item.id,
            kind: kind,
            title: item.name,
            originalTitle: Self.nonEmpty(item.originalTitle),
            synopsis: item.overview,
            releaseYear: item.productionYear,
            rating: item.communityRating,
            durationSeconds: duration,
            posterURL: item.imageTags?["Primary"] == nil
                ? nil
                : imageURL(itemID: item.id, path: "Primary"),
            backdropURL: item.backdropImageTags?.isEmpty == false
                ? imageURL(itemID: item.id, path: "Backdrop/0")
                : nil,
            logoURL: item.imageTags?["Logo"] == nil
                ? nil
                : imageURL(itemID: item.id, path: "Logo"),
            totalSeasons: kind == .series ? item.childCount : nil,
            genres: Self.genres(item.genres),
            userState: Self.userState(item)
        )
        var keys = Set<ContentKey>()
        if let tmdb = item.providerIDs?["Tmdb"] { keys.insert(.tmdb(tmdb)) }
        if let imdb = item.providerIDs?["Imdb"] { keys.insert(.imdb(imdb)) }
        return LocatedMediaItem(
            locator: MediaLocatorID(
                sourceID: configuration.sourceID,
                providerItemID: item.id
            ),
            contentKeys: keys,
            summary: summary
        )
    }

    func continueWatchingItem(
        _ item: ItemDTO,
        series: MediaLocatorID
    ) -> ContinueWatchingItem? {
        guard Self.mediaKind(item.type) == .episode else { return nil }
        return ContinueWatchingItem(
            id: "episode:\(item.id)",
            item: PlayableItem(id: item.id, kind: .episode),
            mediaID: item.seriesID ?? series.providerItemID,
            title: item.name,
            subtitle: nil,
            posterURL: imageURL(itemID: series.providerItemID, path: "Primary"),
            thumbnailURL: item.imageTags?["Primary"] == nil
                ? nil
                : imageURL(itemID: item.id, path: "Primary"),
            durationSeconds: item.runTimeTicks.map { Double($0) / 10_000_000 },
            seasonID: item.seasonID,
            seasonNumber: item.parentIndexNumber,
            episodeNumber: item.indexNumber,
            userState: Self.userState(item)
        )
    }

    static func userState(_ item: ItemDTO) -> UserPlaybackState {
        let duration = item.runTimeTicks.map { Double($0) / 10_000_000 }
        let position = Double(item.userData?.playbackPositionTicks ?? 0) / 10_000_000
        let progress = duration.flatMap { $0 > 0 ? position / $0 : nil } ?? 0
        return UserPlaybackState(
            played: item.userData?.played ?? false,
            favorite: item.userData?.isFavorite,
            positionSeconds: position,
            progress: progress,
            lastPlayedAt: Self.date(item.userData?.lastPlayedDate)
        )
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func genres(_ values: [String]?) -> [Genre] {
        var seen = Set<String>()
        return (values ?? []).compactMap { value in
            guard let genre = Genre.normalized(name: value) else { return nil }
            return seen.insert(genre.slug).inserted ? genre : nil
        }
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return try? Date.ISO8601FormatStyle(
            includingFractionalSeconds: value.contains(".")
        ).parse(value)
    }

    func imageURL(itemID: String, path: String) -> URL {
        path.split(separator: "/").reduce(
            configuration.baseURL
                .appendingPathComponent("Items")
                .appendingPathComponent(itemID)
                .appendingPathComponent("Images")
        ) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    static func collectionKind(_ value: String?) -> MediaKind? {
        switch value?.lowercased() {
        case "movies": .movie
        case "tvshows": .series
        default: nil
        }
    }

    static func mediaKind(_ value: String) -> MediaKind? {
        switch value.lowercased() {
        case "movie": .movie
        case "series": .series
        case "episode": .episode
        default: nil
        }
    }

    static func embyType(_ kind: MediaKind) -> String {
        switch kind {
        case .movie: "Movie"
        case .series: "Series"
        case .episode: "Episode"
        }
    }

    static func nextCursor(
        offset: Int,
        consumedCount: Int,
        total: Int
    ) throws -> MediaCursor? {
        let nextOffset = offset + consumedCount
        if nextOffset >= total {
            return nil
        }
        guard consumedCount > 0 else {
            throw MediaSourceFailure.invalidResponse
        }
        return MediaCursor(rawValue: String(nextOffset))
    }

    static func isHTTPOrigin(_ components: URLComponents) -> Bool {
        guard let scheme = components.scheme?.lowercased(), components.host != nil else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    static func isSameOrigin(
        _ lhs: URLComponents,
        _ rhs: URLComponents
    ) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    static func effectivePort(_ components: URLComponents) -> Int? {
        if let port = components.port { return port }
        switch components.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    static func embySort(_ field: MediaSort.Field) -> String {
        switch field {
        case .releaseDate: "PremiereDate"
        case .updatedAt, .assetUpdatedAt: "DateCreated"
        case .title: "SortName"
        case .rating: "CommunityRating"
        case .popularity: "PlayCount"
        }
    }
}
