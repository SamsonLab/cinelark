import Foundation
import CineLarkDomain
import CineLarkPluginAPI

actor EmbyService {
    private static let summaryFields = [
        "Overview",
        "ProviderIds",
        "UserData",
        "RunTimeTicks",
        "OriginalTitle",
        "Genres"
    ]

    let configuration: SourceConfiguration
    private let device: EmbyDeviceIdentity
    private let http: EmbyHTTPClient
    private let tokenVault: EmbyTokenVault
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

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

    func page(query: MediaQuery, searchTerm: String? = nil) async throws -> MediaPage {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let offset = query.cursor.flatMap { Int($0.rawValue) } ?? 0
        var items = [
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "StartIndex", value: String(offset)),
            URLQueryItem(name: "Limit", value: String(query.limit)),
            URLQueryItem(name: "Fields", value: Self.summaryFields.joined(separator: ","))
        ]
        if !query.kinds.isEmpty {
            items.append(
                URLQueryItem(
                    name: "IncludeItemTypes",
                    value: query.kinds.map(Self.embyType).sorted().joined(separator: ",")
                )
            )
        }
        if let parent = query.parent {
            items.append(URLQueryItem(name: "ParentId", value: parent.providerItemID))
        }
        if let searchTerm, !searchTerm.isEmpty {
            items.append(URLQueryItem(name: "SearchTerm", value: searchTerm))
        }
        for filter in query.filters {
            switch filter {
            case let .favorite(value):
                items.append(URLQueryItem(name: "IsFavorite", value: String(value)))
            case let .played(value):
                items.append(URLQueryItem(name: "IsPlayed", value: String(value)))
            case let .resumable(value) where value:
                items.append(URLQueryItem(name: "Filters", value: "IsResumable"))
            default:
                break
            }
        }
        if let sort = query.sort {
            items.append(URLQueryItem(name: "SortBy", value: Self.embySort(sort.field)))
            items.append(
                URLQueryItem(
                    name: "SortOrder",
                    value: sort.order == .ascending ? "Ascending" : "Descending"
                )
            )
        }
        let request = try builder.request(
            path: "Users/\(userID)/Items",
            query: items,
            token: token
        )
        let page: ItemPageDTO = try await response(for: request)
        let located = page.items.compactMap { map($0) }
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

    func collections() async throws -> [MediaCollection] {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let request = try builder.request(path: "Users/\(userID)/Views", token: token)
        let page: ItemPageDTO = try await response(for: request)
        return page.items.enumerated().map { index, item in
            MediaCollection(
                id: item.id,
                name: item.name,
                mediaKind: Self.collectionKind(item.collectionType),
                order: index,
                itemCount: item.childCount ?? 0
            )
        }
    }

    func latest(query: MediaQuery) async throws -> MediaPage {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        var queryItems = [
            URLQueryItem(name: "Limit", value: String(query.limit)),
            URLQueryItem(
                name: "Fields",
                value: (Self.summaryFields + ["People"]).joined(separator: ",")
            )
        ]
        if let parent = query.parent {
            queryItems.append(URLQueryItem(name: "ParentId", value: parent.providerItemID))
        }
        if !query.kinds.isEmpty {
            queryItems.append(URLQueryItem(
                name: "IncludeItemTypes",
                value: query.kinds.map(Self.embyType).sorted().joined(separator: ",")
            ))
        }
        let request = try builder.request(
            path: "Users/\(userID)/Items/Latest",
            query: queryItems,
            token: token
        )
        let items: [ItemDTO] = try await response(for: request)
        let located = items.compactMap(map)
        return MediaPage(items: located, nextCursor: nil, total: located.count)
    }

    func resume(query: MediaQuery) async throws -> MediaPage {
        try await specialPage(pathSuffix: "Items/Resume", query: query)
    }

    func detail(locator: MediaLocatorID) async throws -> MediaDetail {
        let item = try await item(id: locator.providerItemID)
        guard let located = map(item) else { throw MediaSourceFailure.invalidResponse }
        let credits = (item.people ?? []).enumerated().compactMap { index, person
            -> (String?, PersonCredit)? in
            guard let id = person.id else { return nil }
            return (
                person.type?.lowercased(),
                PersonCredit(
                    id: id,
                    name: person.name,
                    character: person.role,
                    avatarURL: person.primaryImageTag == nil
                        ? nil
                        : imageURL(itemID: id, path: "Primary"),
                    order: index
                )
            )
        }
        let directors = credits.compactMap { $0.0 == "director" ? $0.1 : nil }
        let cast = credits.compactMap { $0.0 == "actor" ? $0.1 : nil }
        return MediaDetail(
            summary: located.summary,
            directors: directors,
            cast: cast,
            tmdbID: item.providerIDs?["Tmdb"],
            imdbID: item.providerIDs?["Imdb"]
        )
    }

    func seasons(series: MediaLocatorID) async throws -> [Season] {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let request = try builder.request(
            path: "Shows/\(series.providerItemID)/Seasons",
            query: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "Fields", value: "UserData")
            ],
            token: token
        )
        let page: ItemPageDTO = try await response(for: request)
        return page.items.map { item in
            Season(
                id: item.id,
                seriesID: series.providerItemID,
                number: item.indexNumber ?? 0,
                title: item.name,
                posterURL: item.imageTags?["Primary"] == nil
                    ? nil
                    : imageURL(itemID: item.id, path: "Primary"),
                episodeCount: item.childCount ?? 0,
                userState: Self.userState(item)
            )
        }
    }

    func episodes(
        series: MediaLocatorID,
        seasonID: String,
        page requestPage: PageRequest
    ) async throws -> Page<Episode> {
        let token = try await requiredToken()
        guard let userID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let start = (requestPage.number - 1) * requestPage.size
        let request = try builder.request(
            path: "Shows/\(series.providerItemID)/Episodes",
            query: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "SeasonId", value: seasonID),
                URLQueryItem(name: "StartIndex", value: String(start)),
                URLQueryItem(name: "Limit", value: String(requestPage.size)),
                URLQueryItem(name: "Fields", value: "Overview,UserData,RunTimeTicks,MediaSourceCount")
            ],
            token: token
        )
        let page: ItemPageDTO = try await response(for: request)
        return Page(
            number: requestPage.number,
            size: requestPage.size,
            total: page.totalRecordCount,
            items: page.items.map { item in
                Episode(
                    id: item.id,
                    seriesID: item.seriesID ?? series.providerItemID,
                    seasonID: item.seasonID ?? seasonID,
                    number: item.indexNumber ?? 0,
                    title: item.name,
                    synopsis: item.overview,
                    airDate: item.premiereDate,
                    thumbnailURL: item.imageTags?["Primary"] == nil
                        ? nil
                        : imageURL(itemID: item.id, path: "Primary"),
                    durationSeconds: item.runTimeTicks.map { Double($0) / 10_000_000 },
                    versionCount: item.mediaSourceCount ?? 0,
                    hasMultipleVersions: (item.mediaSourceCount ?? 0) > 1,
                    userState: Self.userState(item)
                )
            }
        )
    }

    func person(id: String) async throws -> PersonDetail {
        let value = try await item(id: id)
        return PersonDetail(
            id: value.id,
            name: value.name,
            avatarURL: value.imageTags?["Primary"] == nil
                ? nil
                : imageURL(itemID: value.id, path: "Primary"),
            isFavorite: value.userData?.isFavorite ?? false,
            tmdbID: value.providerIDs?["Tmdb"],
            imdbID: value.providerIDs?["Imdb"]
        )
    }

    func works(personID: String, query: MediaQuery) async throws -> MediaPage {
        try await specialPage(
            pathSuffix: "Items",
            query: query,
            additional: [URLQueryItem(name: "PersonIds", value: personID)]
        )
    }

    func artwork(locator: MediaLocatorID, kind: String) async throws -> ArtworkDescriptor {
        let token = try await requiredToken()
        let imageType = kind.lowercased() == "backdrop" ? "Backdrop/0" : "Primary"
        let request = try builder.request(
            path: "Items/\(locator.providerItemID)/Images/\(imageType)",
            token: token
        )
        return ArtworkDescriptor(
            url: request.url!,
            headers: ["X-Emby-Authorization": request.value(forHTTPHeaderField: "X-Emby-Authorization")!]
        )
    }

    func playback(locator: MediaLocatorID) async throws -> SourcePlaybackDescriptor {
        let token = try await requiredToken()
        let body = try encoder.encode(["DeviceProfile": [String: String]()])
        let request = try builder.request(
            path: "Items/\(locator.providerItemID)/PlaybackInfo",
            method: "POST",
            token: token,
            body: body
        )
        let info: PlaybackInfoDTO = try await response(for: request)
        guard let source = info.mediaSources.first(where: {
            $0.supportsDirectPlay == true || $0.supportsDirectStream == true
        }) else {
            throw MediaSourceFailure.unsupported("No direct-playable Emby media source")
        }
        let url: URL
        if let streamPath = source.directStreamURL, !streamPath.isEmpty {
            url = try directStreamURL(from: streamPath)
        } else {
            url = try builder.request(
                path: "Videos/\(locator.providerItemID)/stream",
                query: [
                    URLQueryItem(name: "static", value: "true"),
                    URLQueryItem(name: "MediaSourceId", value: source.id)
                ],
                token: token
            ).url!
        }
        return SourcePlaybackDescriptor(
            url: url,
            headers: ["X-Emby-Authorization": try authorizationHeader(token: token)],
            mode: source.supportsDirectPlay == true ? .directPlay : .directStream,
            mediaSourceID: source.id
        )
    }

    func report(_ event: PlaybackEvent) async throws {
        let token = try await requiredToken()
        let path: String
        let locator: MediaLocatorID
        let position: Double
        let isPaused: Bool
        switch event {
        case let .started(value, seconds):
            path = "Sessions/Playing"
            locator = value
            position = seconds
            isPaused = false
        case let .progress(value, seconds, paused):
            path = "Sessions/Playing/Progress"
            locator = value
            position = seconds
            isPaused = paused
        case let .stopped(value, seconds, _):
            path = "Sessions/Playing/Stopped"
            locator = value
            position = seconds
            isPaused = false
        }
        let payload: [String: Any] = [
            "ItemId": locator.providerItemID,
            "PositionTicks": Int64(max(position, 0) * 10_000_000),
            "IsPaused": isPaused
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let request = try builder.request(path: path, method: "POST", token: token, body: data)
        try await sendMutation(request)
    }

    func importRemoteState() async throws -> RemoteStateSnapshot {
        guard let remoteUserID = configuration.remoteUserID else {
            throw MediaSourceFailure.unauthorized
        }
        let base = MediaQuery(scope: SourceScope(sourceID: configuration.sourceID), limit: 200)
        let favorites = try await collectPages(
            initial: MediaQuery(
                scope: base.scope,
                kinds: [.movie, .series],
                filters: [.favorite(true)],
                limit: base.limit
            ),
            fetch: { try await self.page(query: $0) }
        )
        let resumable = try await collectPages(
            initial: base,
            fetch: { try await self.resume(query: $0) }
        )
        var values: [MediaLocatorID: RemoteMediaState] = [:]
        for item in favorites {
            values[item.locator] = RemoteMediaState(
                locator: item.locator,
                summary: item.summary,
                isFavorite: true,
                playback: item.summary.userState.positionSeconds > 0 || item.summary.userState.played
                    ? item.summary.userState
                    : nil
            )
        }
        for item in resumable {
            let current = values[item.locator]
            values[item.locator] = RemoteMediaState(
                locator: item.locator,
                summary: item.summary,
                isFavorite: current?.isFavorite ?? item.summary.userState.favorite,
                playback: item.summary.userState
            )
        }
        return RemoteStateSnapshot(
            marker: "emby-v1:\(configuration.serverIdentity.serverID):\(remoteUserID)",
            remoteUserID: remoteUserID,
            items: values.values.sorted {
                $0.locator.providerItemID < $1.locator.providerItemID
            }
        )
    }

    func mirrorRemoteState(userID: String, mutation: RemoteStateMutation) async throws {
        let token = try await requiredToken()
        guard configuration.remoteUserID == userID else {
            throw MediaSourceFailure.unauthorized
        }
        switch mutation {
        case let .favorite(locator, isFavorite):
            let request = try builder.request(
                path: "Users/\(userID)/FavoriteItems/\(locator.providerItemID)",
                method: isFavorite ? "POST" : "DELETE",
                token: token
            )
            try await sendMutation(request)

        case let .playback(locator, state):
            try await report(.progress(
                locator: locator,
                positionSeconds: state.positionSeconds,
                isPaused: true
            ))
            let request = try builder.request(
                path: "Users/\(userID)/PlayedItems/\(locator.providerItemID)",
                method: state.played ? "POST" : "DELETE",
                token: token
            )
            try await sendMutation(request)
        }
    }

    private var builder: EmbyRequestBuilder {
        EmbyRequestBuilder(baseURL: configuration.baseURL, device: device)
    }

    private func requiredToken() async throws -> String {
        guard let token = try await tokenVault.load(configuration.sourceID), !token.isEmpty else {
            throw MediaSourceFailure.unauthorized
        }
        return token
    }

    private func response<Value: Decodable>(for request: URLRequest) async throws -> Value {
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

    private func sendMutation(_ request: URLRequest) async throws {
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

    private func item(id: String) async throws -> ItemDTO {
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

    private func specialPage(
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

    private func collectPages(
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

    private func directStreamURL(from reference: String) throws -> URL {
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
        if let queryItems = resolvedComponents.queryItems {
            let safeItems = queryItems.filter { !Self.isCredentialQueryName($0.name) }
            resolvedComponents.queryItems = safeItems.isEmpty ? nil : safeItems
        }
        guard let sanitizedURL = resolvedComponents.url else {
            throw MediaSourceFailure.invalidResponse
        }
        return sanitizedURL
    }

    private func authorizationHeader(token: String) throws -> String {
        let request = try builder.request(path: "", token: token)
        return request.value(forHTTPHeaderField: "X-Emby-Authorization") ?? ""
    }

    private func map(_ item: ItemDTO) -> LocatedMediaItem? {
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

    private static func userState(_ item: ItemDTO) -> UserPlaybackState {
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

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func genres(_ values: [String]?) -> [Genre] {
        var seen = Set<String>()
        return (values ?? []).compactMap { value in
            guard let genre = Genre.normalized(name: value) else { return nil }
            return seen.insert(genre.slug).inserted ? genre : nil
        }
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return try? Date.ISO8601FormatStyle(
            includingFractionalSeconds: value.contains(".")
        ).parse(value)
    }

    private func imageURL(itemID: String, path: String) -> URL {
        path.split(separator: "/").reduce(
            configuration.baseURL
                .appendingPathComponent("Items")
                .appendingPathComponent(itemID)
                .appendingPathComponent("Images")
        ) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    private static func collectionKind(_ value: String?) -> MediaKind? {
        switch value?.lowercased() {
        case "movies": .movie
        case "tvshows": .series
        default: nil
        }
    }

    private static func mediaKind(_ value: String) -> MediaKind? {
        switch value.lowercased() {
        case "movie": .movie
        case "series": .series
        case "episode": .episode
        default: nil
        }
    }

    private static func embyType(_ kind: MediaKind) -> String {
        switch kind {
        case .movie: "Movie"
        case .series: "Series"
        case .episode: "Episode"
        }
    }

    private static func nextCursor(
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

    private static func isHTTPOrigin(_ components: URLComponents) -> Bool {
        guard let scheme = components.scheme?.lowercased(), components.host != nil else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private static func isSameOrigin(
        _ lhs: URLComponents,
        _ rhs: URLComponents
    ) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ components: URLComponents) -> Int? {
        if let port = components.port { return port }
        switch components.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    private static func isCredentialQueryName(_ name: String) -> Bool {
        let normalized = name.lowercased().filter(\.isLetter)
        return [
            "apikey",
            "token",
            "xembytoken",
            "accesstoken",
            "auth",
            "authorization",
            "signature",
            "sig"
        ].contains(normalized)
    }

    private static func embySort(_ field: MediaSort.Field) -> String {
        switch field {
        case .releaseDate: "PremiereDate"
        case .updatedAt, .assetUpdatedAt: "DateCreated"
        case .title: "SortName"
        case .rating: "CommunityRating"
        case .popularity: "PlayCount"
        }
    }
}
