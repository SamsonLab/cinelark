import Foundation
import CineLarkDomain

public actor UHDNowProvider: MediaLibraryProvider {
    private let configuration: UHDNowConfiguration
    private let sessionStore: any ProviderSessionStore
    private let transport: any HTTPTransport
    private let requestBuilder: UHDNowRequestBuilder
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var session: ProviderSession?
    private var resolvedDeliveryURL: URL?

    public init(
        configuration: UHDNowConfiguration = .production,
        sessionStore: any ProviderSessionStore,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.configuration = configuration
        self.sessionStore = sessionStore
        self.transport = transport
        self.requestBuilder = UHDNowRequestBuilder(configuration: configuration)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    public func restoreSession() async throws -> ProviderSession? {
        guard let stored = try await sessionStore.load() else {
            return nil
        }
        guard !stored.isExpired else {
            try await sessionStore.clear()
            return nil
        }
        session = stored
        return stored
    }

    public func signIn(credentials: ProviderCredentials) async throws -> ProviderSession {
        let body = try encoder.encode(
            LoginRequest(
                username: credentials.username,
                password: credentials.password,
                totpCode: credentials.totpCode ?? ""
            )
        )
        let login: LoginDTO = try await request(
            method: .post,
            path: UHDNowRequestBuilder.path("auth", "login"),
            body: body,
            authenticated: false
        )
        guard !login.token.isEmpty, let expiresAt = parseDate(login.expiresAt) else {
            throw ProviderError.invalidResponse
        }

        let issued = ProviderSession(token: login.token, expiresAt: expiresAt)
        try await sessionStore.save(issued)
        session = issued
        resolvedDeliveryURL = nil
        return issued
    }

    public func signOut() async {
        if session != nil {
            try? await requestBasic(
                method: .post,
                path: UHDNowRequestBuilder.path("users", "me", "logout"),
                authenticated: true
            )
        }
        session = nil
        resolvedDeliveryURL = nil
        try? await sessionStore.clear()
    }

    public func hot(page: PageRequest) async throws -> Page<MediaSummary> {
        let data: PagedDTO<MediaSummaryDTO> = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path("stream", "library", "hot"),
            queryItems: paging(page)
        )
        return mapPage(data)
    }

    public func collections() async throws -> [MediaCollection] {
        let data: CollectionsDataDTO = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path("stream", "library", "collections")
        )
        return data.items
            .map(mapCollection)
            .sorted { lhs, rhs in lhs.order < rhs.order }
    }

    public func items(
        in collectionID: String,
        page: PageRequest,
        sort: MediaSort? = .newest
    ) async throws -> Page<MediaSummary> {
        var query = paging(page)
        if let sort {
            query.append(URLQueryItem(name: "sort_by", value: sort.field.rawValue))
            query.append(URLQueryItem(name: "sort_order", value: sort.order.rawValue))
        }
        let data: CollectionItemsDTO = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path(
                "stream", "library", "collections", collectionID, "items"
            ),
            queryItems: query
        )
        return Page(
            number: data.page,
            size: data.pageSize,
            total: data.total,
            items: data.items.compactMap(mapSummary)
        )
    }

    public func search(_ query: String, page: PageRequest) async throws -> Page<MediaSummary> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Page(number: page.number, size: page.size, total: 0, items: [])
        }
        let data: PagedDTO<MediaSummaryDTO> = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path("stream", "library", "search"),
            queryItems: [URLQueryItem(name: "q", value: trimmed)] + paging(page)
        )
        return mapPage(data)
    }

    public func detail(for item: MediaSummary) async throws -> MediaDetail {
        let resource: String
        switch item.kind {
        case .movie: resource = "movies"
        case .series: resource = "tv"
        }
        let data: MediaDetailDTO = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path("stream", resource, item.id)
        )
        guard let summary = mapSummary(data) else {
            throw ProviderError.invalidResponse
        }
        return MediaDetail(
            summary: summary,
            directors: (data.directors ?? []).map(mapCredit),
            cast: (data.cast ?? []).map(mapCredit),
            tmdbID: data.tmdbId?.value,
            imdbID: data.imdbId
        )
    }

    public func seasons(seriesID: String) async throws -> [Season] {
        let data: SeasonsDataDTO = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path("stream", "tv", seriesID, "seasons")
        )
        return data.items.map { value in
            Season(
                id: value.id,
                seriesID: value.mediaId,
                number: value.seasonNumber,
                title: value.seasonTitle,
                posterURL: imageURL(value.posterPath),
                episodeCount: value.totalEpisodes,
                userState: mapUserState(value.userState)
            )
        }.sorted { $0.number < $1.number }
    }

    public func episodes(
        seriesID: String,
        seasonID: String,
        page: PageRequest
    ) async throws -> Page<Episode> {
        let data: PagedDTO<EpisodeDTO> = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path(
                "stream", "tv", seriesID, "seasons", seasonID, "episodes"
            ),
            queryItems: paging(page)
        )
        return Page(
            number: data.page,
            size: data.pageSize,
            total: data.total,
            items: data.items.map { value in
                Episode(
                    id: value.id,
                    seriesID: value.mediaId,
                    seasonID: value.seasonId,
                    number: value.episodeNumber,
                    title: value.title,
                    synopsis: value.description,
                    airDate: value.airDate,
                    thumbnailURL: imageURL(value.thumbPath),
                    durationSeconds: value.duration,
                    versionCount: value.hasVersions ?? 0,
                    hasMultipleVersions: (value.hasVersions ?? 0) > 0,
                    userState: mapUserState(value.userState)
                )
            }
        )
    }

    public func person(id: String) async throws -> PersonDetail {
        let data: PersonDetailDTO = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path("stream", "library", "persons", id)
        )
        return mapPerson(data)
    }

    public func works(
        forPersonID personID: String,
        page: PageRequest,
        sort: MediaSort? = .newest
    ) async throws -> Page<MediaSummary> {
        var query = paging(page)
        if let sort {
            query.append(URLQueryItem(name: "sort_by", value: sort.field.rawValue))
            query.append(URLQueryItem(name: "sort_order", value: sort.order.rawValue))
        }
        let data: PagedDTO<MediaSummaryDTO> = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path(
                "stream", "library", "persons", personID, "works"
            ),
            queryItems: query
        )
        return mapPage(data)
    }

    public func favoriteMedia(
        kind: MediaKind,
        page: PageRequest
    ) async throws -> Page<MediaSummary> {
        let data: PagedDTO<MediaSummaryDTO> = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path("stream", "me", "favorites"),
            queryItems: [
                URLQueryItem(name: "type", value: favoriteType(for: kind))
            ] + paging(page)
        )
        return mapPage(data)
    }

    public func favoritePeople(page: PageRequest) async throws -> Page<PersonDetail> {
        let data: PagedDTO<PersonDetailDTO> = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path("stream", "me", "favorites"),
            queryItems: [URLQueryItem(name: "type", value: "person")] + paging(page)
        )
        return Page(
            number: data.page,
            size: data.pageSize,
            total: data.total,
            items: data.items.map(mapPerson)
        )
    }

    public func setFavorite(_ isFavorite: Bool, target: FavoriteTarget) async throws -> Bool {
        let response: FavoriteMutationResponseDTO
        if isFavorite {
            let body = try encoder.encode(
                FavoriteMutationRequest(
                    itemId: target.id,
                    itemType: favoriteType(for: target.kind)
                )
            )
            response = try await request(
                method: .post,
                path: UHDNowRequestBuilder.path("stream", "me", "favorites"),
                body: body
            )
        } else {
            guard target.kind == .series else {
                throw ProviderError.unsupported
            }
            response = try await request(
                method: .delete,
                path: UHDNowRequestBuilder.path(
                    "stream", "me", "favorites", "tv", target.id
                )
            )
        }
        guard response.itemId == target.id,
              response.itemType == favoriteType(for: target.kind) else {
            throw ProviderError.invalidResponse
        }
        return response.favorite
    }

    public func assets(for item: PlayableItem) async throws -> [MediaAsset] {
        let resource = item.kind == .movie ? "movies" : "episodes"
        let data: AssetsDataDTO = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path("stream", resource, item.id, "assets")
        )
        return data.videos.map(mapAsset)
    }

    public func playbackURL(for asset: MediaAsset) async throws -> URL {
        try await capabilityURL(path: asset.playPath)
    }

    public func downloadURL(for asset: MediaAsset) async throws -> URL {
        guard let downloadPath = asset.downloadPath, !downloadPath.isEmpty else {
            throw ProviderError.unsupported
        }
        return try await capabilityURL(path: downloadPath)
    }

    public func playbackShelf(limit: Int) async throws -> PlaybackShelf {
        let data: PlaybackShelvesDTO = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path("stream", "me", "playback-states"),
            queryItems: [URLQueryItem(name: "page_size", value: String(max(limit, 1)))]
        )
        return PlaybackShelf(
            resume: data.resume.compactMap { mapContinue($0.resume) },
            nextUp: data.nextUp.compactMap { mapContinue($0.nextUp ?? $0.resume) }
        )
    }

    public func reportProgress(_ update: PlaybackUpdate) async throws -> UserPlaybackState {
        try await report(update, endpoint: "progress")
    }

    public func reportStopped(_ update: PlaybackUpdate) async throws -> UserPlaybackState {
        try await report(update, endpoint: "stopped")
    }

    private func report(_ update: PlaybackUpdate, endpoint: String) async throws -> UserPlaybackState {
        let body = try encoder.encode(
            PlaybackUpdateRequest(
                assetId: update.assetID,
                itemId: update.item.id,
                itemType: update.item.kind.rawValue,
                positionTicks: UHDNowTime.ticks(fromSeconds: update.positionSeconds)
            )
        )
        let data: PlaybackUpdateResponseDTO = try await request(
            method: .post,
            path: UHDNowRequestBuilder.path("stream", "playback", endpoint),
            body: body
        )
        return mapUserState(data.userState)
    }

    private func request<Value: Decodable>(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        authenticated: Bool = true
    ) async throws -> Value {
        let token = authenticated ? try await authenticatedSession().token : nil
        let request: URLRequest
        do {
            request = try requestBuilder.request(
                method: method,
                path: path,
                queryItems: queryItems,
                token: token,
                body: body
            )
        } catch {
            throw ProviderError.invalidRequest
        }

        let result: HTTPResult
        do {
            result = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProviderError.unavailable
        }

        try await validate(
            statusCode: result.statusCode,
            authenticated: authenticated
        )
        do {
            let envelope = try decoder.decode(APIEnvelope<Value>.self, from: result.data)
            guard envelope.ok else {
                throw ProviderError.invalidResponse
            }
            return envelope.data
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.invalidResponse
        }
    }

    private func requestBasic(
        method: HTTPMethod,
        path: String,
        authenticated: Bool
    ) async throws {
        let token = authenticated ? try await authenticatedSession().token : nil
        let request = try requestBuilder.request(method: method, path: path, token: token)
        let result = try await transport.send(request)
        try await validate(
            statusCode: result.statusCode,
            authenticated: authenticated
        )
        let response = try decoder.decode(BasicResponse.self, from: result.data)
        guard response.ok else {
            throw ProviderError.invalidResponse
        }
    }

    private func validate(statusCode: Int, authenticated: Bool) async throws {
        switch statusCode {
        case 200..<300:
            return
        case 400 where !authenticated:
            throw ProviderError.invalidCredentials
        case 401 where !authenticated:
            throw ProviderError.invalidCredentials
        case 401:
            session = nil
            resolvedDeliveryURL = nil
            try? await sessionStore.clear()
            throw ProviderError.sessionExpired
        case 403:
            throw ProviderError.forbidden
        case 404:
            throw ProviderError.notFound
        case 429:
            throw ProviderError.rateLimited
        case 500...:
            throw ProviderError.unavailable
        default:
            throw ProviderError.invalidResponse
        }
    }

    private func authenticatedSession() async throws -> ProviderSession {
        guard let session else {
            throw ProviderError.unauthenticated
        }
        guard !session.isExpired else {
            self.session = nil
            resolvedDeliveryURL = nil
            try? await sessionStore.clear()
            throw ProviderError.sessionExpired
        }
        return session
    }

    private func capabilityURL(path: String) async throws -> URL {
        let current = try await authenticatedSession()
        let deliveryURL = try await deliveryBaseURL()
        guard let assetURL = URL(string: path, relativeTo: deliveryURL)?.absoluteURL,
              var components = URLComponents(
                  url: assetURL,
                  resolvingAgainstBaseURL: false
              ) else {
            throw ProviderError.invalidResponse
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name.caseInsensitiveCompare("token") == .orderedSame }
        queryItems.append(URLQueryItem(name: "token", value: current.token))
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ProviderError.invalidResponse
        }
        return url
    }

    private func deliveryBaseURL() async throws -> URL {
        if let resolvedDeliveryURL {
            return resolvedDeliveryURL
        }
        let domains: [DeliveryDomainDTO] = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path("subscriptions", "domains")
        )
        guard let selected = domains.sorted(by: { $0.sortOrder < $1.sortOrder }).first else {
            throw ProviderError.invalidResponse
        }
        let resolved: DeliveryDomainDTO = try await request(
            method: .get,
            path: UHDNowRequestBuilder.path(
                "subscriptions", "domains", selected.id, "resolve"
            )
        )
        guard let url = URL(string: resolved.domain),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" else {
            throw ProviderError.invalidResponse
        }
        resolvedDeliveryURL = url
        return url
    }

    private func paging(_ page: PageRequest) -> [URLQueryItem] {
        [
            URLQueryItem(name: "page", value: String(page.number)),
            URLQueryItem(name: "page_size", value: String(page.size))
        ]
    }

    private func mapPage(_ data: PagedDTO<MediaSummaryDTO>) -> Page<MediaSummary> {
        Page(
            number: data.page,
            size: data.pageSize,
            total: data.total,
            items: data.items.compactMap(mapSummary)
        )
    }

    private func mapSummary(_ value: MediaSummaryDTO) -> MediaSummary? {
        guard let kind = mediaKind(value.type) else { return nil }
        return MediaSummary(
            id: value.id,
            kind: kind,
            title: value.title,
            originalTitle: value.originTitle,
            synopsis: value.description,
            releaseYear: value.releaseYear,
            rating: value.rating,
            durationSeconds: value.duration,
            posterURL: imageURL(value.posterPath),
            backdropURL: imageURL(value.fanartPath),
            logoURL: imageURL(value.logoPath),
            totalSeasons: value.totalSeasons,
            hasMultipleVersions: (value.hasVersions ?? 0) > 0,
            genres: (value.genres ?? []).map {
                Genre(id: $0.id, name: $0.name, slug: $0.slug)
            },
            userState: mapUserState(value.userState)
        )
    }

    private func mapSummary(_ value: MediaDetailDTO) -> MediaSummary? {
        guard let kind = mediaKind(value.type) else { return nil }
        return MediaSummary(
            id: value.id,
            kind: kind,
            title: value.title,
            originalTitle: value.originTitle,
            synopsis: value.description,
            releaseYear: value.releaseYear,
            rating: value.rating,
            durationSeconds: value.duration,
            posterURL: imageURL(value.posterPath),
            backdropURL: imageURL(value.fanartPath),
            logoURL: imageURL(value.logoPath),
            totalSeasons: value.totalSeasons,
            hasMultipleVersions: (value.hasVersions ?? 0) > 0,
            genres: (value.genres ?? []).map {
                Genre(id: $0.id, name: $0.name, slug: $0.slug)
            },
            userState: mapUserState(value.userState)
        )
    }

    private func mapCollection(_ value: CollectionDTO) -> MediaCollection {
        MediaCollection(
            id: value.id,
            name: value.name,
            mediaKind: value.mediaType.flatMap(mediaKind),
            order: value.ord,
            itemCount: value.itemCount
        )
    }

    private func mapCredit(_ value: PersonCreditDTO) -> PersonCredit {
        PersonCredit(
            id: value.id,
            name: value.name,
            character: value.character,
            avatarURL: imageURL(value.avatarPath),
            order: value.sortOrder
        )
    }

    private func mapPerson(_ value: PersonDetailDTO) -> PersonDetail {
        PersonDetail(
            id: value.id,
            name: value.name,
            avatarURL: imageURL(value.avatarPath),
            isFavorite: value.favorite ?? false,
            tmdbID: value.tmdbId?.value,
            imdbID: value.imdbId
        )
    }

    private func mapAsset(_ value: VideoAssetDTO) -> MediaAsset {
        MediaAsset(
            id: value.assetId,
            mediaID: value.mediaId,
            episodeID: value.episodeId,
            name: value.name,
            displayName: value.displayName ?? value.name ?? value.resolution ?? "Media",
            container: value.container,
            durationSeconds: value.duration,
            fileSize: value.fileSize,
            bitRate: value.bitRate,
            width: value.width,
            height: value.height,
            resolution: value.resolution,
            encoding: value.encoding,
            profile: value.profile,
            videoBitRate: value.videoBitRate,
            pixelFormat: value.pixFmt,
            frameRate: value.frameRate,
            colorSpace: value.colorSpace,
            colorTransfer: value.colorTransfer,
            colorPrimaries: value.colorPrimaries,
            videoRange: value.videoRange,
            audioTracks: (value.audioTracks ?? []).map { track in
                AudioTrack(
                    index: track.index,
                    codec: track.codecName,
                    bitRate: track.bitRate,
                    channels: track.channels,
                    channelLayout: track.channelLayout,
                    sampleRate: track.sampleRate,
                    language: track.language,
                    title: track.title,
                    isDefault: track.isDefault ?? false
                )
            },
            subtitleTracks: (value.subtitleTracks ?? []).map { track in
                SubtitleTrack(
                    index: track.index,
                    codec: track.codecName,
                    language: track.language,
                    title: track.title,
                    isDefault: track.isDefault ?? false
                )
            },
            playPath: value.playPath,
            downloadPath: value.downloadPath
        )
    }

    private func mapContinue(_ value: ContinueItemDTO?) -> ContinueWatchingItem? {
        guard let value,
              let itemID = value.itemId,
              let itemType = value.itemType,
              let mediaID = value.mediaId,
              let title = value.title,
              let kind = playableKind(itemType) else {
            return nil
        }
        return ContinueWatchingItem(
            id: "\(kind.rawValue):\(itemID)",
            item: PlayableItem(id: itemID, kind: kind),
            mediaID: mediaID,
            title: title,
            subtitle: value.subtitle,
            posterURL: imageURL(value.posterPath),
            thumbnailURL: imageURL(value.thumbPath),
            durationSeconds: value.duration,
            userState: mapUserState(value.userState)
        )
    }

    private func mapUserState(_ value: UserStateDTO?) -> UserPlaybackState {
        guard let value else { return .empty }
        return UserPlaybackState(
            played: value.played ?? false,
            favorite: value.favorite,
            positionSeconds: UHDNowTime.seconds(fromTicks: value.positionTicks ?? 0),
            progress: (value.progressPct ?? 0) / 100,
            lastPlayedAt: value.lastPlayedAt.flatMap(parseDate)
        )
    }

    private func mediaKind(_ value: String) -> MediaKind? {
        switch value.lowercased() {
        case "movie": .movie
        case "tv", "series": .series
        default: nil
        }
    }

    private func playableKind(_ value: String) -> PlayableKind? {
        switch value.lowercased() {
        case "movie": .movie
        case "episode": .episode
        default: nil
        }
    }

    private func favoriteType(for kind: MediaKind) -> String {
        kind == .movie ? "movie" : "tv"
    }

    private func favoriteType(for kind: FavoriteKind) -> String {
        switch kind {
        case .movie: "movie"
        case .series: "tv"
        case .person: "person"
        }
    }

    private func imageURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path, relativeTo: configuration.webBaseURL)?.absoluteURL
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
