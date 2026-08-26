import Foundation
import CineLarkDomain
import CineLarkPluginAPI

public struct UHDNowPluginFactory: MediaSourcePluginFactory {
    public static let pluginID: PluginID = "com.samsonlab.cinelark.uhdnow"

    public let descriptor = CineLarkPluginDescriptor(
        id: Self.pluginID,
        contractVersion: 1,
        displayName: "UHDNow",
        roles: [.mediaSource],
        setupModes: [.manualURL],
        authenticationModes: [.usernamePassword],
        capabilities: CapabilityDescriptor(
            itemKinds: [.movie, .series],
            sortFields: Set(MediaSort.Field.allCases),
            filters: ["favorite", "played", "resumable"],
            pagination: .page,
            playbackModes: [.directPlay],
            mutations: [.favorite, .played, .progress]
        )
    )

    private let makeProvider: @Sendable (SourceConfiguration) -> any MediaLibraryProvider

    public init(
        makeProvider: @escaping @Sendable (SourceConfiguration) -> any MediaLibraryProvider
    ) {
        self.makeProvider = makeProvider
    }

    public func validate(baseURL: URL) async throws -> SourceInstanceIdentity {
        guard let host = baseURL.host, !host.isEmpty else {
            throw MediaSourceFailure.invalidResponse
        }
        let normalizedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return SourceInstanceIdentity(
            pluginID: Self.pluginID,
            serverID: normalizedPath.isEmpty ? host : "\(host)/\(normalizedPath)"
        )
    }

    public func makeRuntime(configuration: SourceConfiguration) async throws -> MediaSourceRuntime {
        let adapter = UHDNowRuntimeAdapter(
            sourceID: configuration.sourceID,
            provider: makeProvider(configuration)
        )
        return MediaSourceRuntime(
            sourceID: configuration.sourceID,
            descriptor: descriptor,
            authentication: AuthenticationClient { credentials in
                try await adapter.authenticate(credentials, configuration: configuration)
            },
            browse: BrowseClient { query in
                try await adapter.page(query: query)
            },
            search: SearchClient { term, query in
                try await adapter.search(term: term, query: query)
            },
            hierarchy: HierarchyClient(
                collections: { try await adapter.collections() },
                latest: { try await adapter.page(query: $0) },
                resume: { try await adapter.resume(query: $0) },
                detail: { try await adapter.detail(locator: $0, summary: $1) },
                seasons: { try await adapter.seasons(series: $0) },
                episodes: { try await adapter.episodes(series: $0, seasonID: $1, page: $2) },
                person: { try await adapter.person(id: $0) },
                works: { try await adapter.works(personID: $0, query: $1) }
            ),
            playback: PlaybackResolutionClient { locator in
                try await adapter.playback(locator: locator)
            },
            playbackSession: PlaybackSessionClient { event in
                try await adapter.report(event)
            },
            download: PlaybackResolutionClient { locator in
                try await adapter.download(locator: locator)
            }
        )
    }
}

private actor UHDNowRuntimeAdapter {
    let sourceID: SourceID
    let provider: any MediaLibraryProvider
    private var selectedAssets: [String: MediaAsset] = [:]

    init(sourceID: SourceID, provider: any MediaLibraryProvider) {
        self.sourceID = sourceID
        self.provider = provider
    }

    func authenticate(
        _ credentials: SourceCredentials,
        configuration: SourceConfiguration
    ) async throws -> AuthenticatedSource {
        guard let username = credentials.username, let password = credentials.password else {
            throw MediaSourceFailure.unauthorized
        }
        do {
            let session = try await provider.signIn(
                credentials: ProviderCredentials(username: username, password: password, totpCode: nil)
            )
            return AuthenticatedSource(configuration: configuration, token: session.token)
        } catch {
            throw normalize(error)
        }
    }

    func page(query: MediaQuery) async throws -> MediaPage {
        let offset = query.cursor.flatMap { Int($0.rawValue) } ?? 0
        let pageNumber = (offset / query.limit) + 1
        let request = PageRequest(number: pageNumber, size: query.limit)
        do {
            let page: Page<MediaSummary>
            if let parent = query.parent {
                page = try await provider.items(
                    in: parent.providerItemID,
                    page: request,
                    sort: query.sort
                )
            } else {
                page = try await provider.hot(page: request)
            }
            return map(page, offset: offset)
        } catch {
            throw normalize(error)
        }
    }

    func search(term: String, query: MediaQuery) async throws -> MediaPage {
        let offset = query.cursor.flatMap { Int($0.rawValue) } ?? 0
        let request = PageRequest(number: (offset / query.limit) + 1, size: query.limit)
        do {
            return map(try await provider.search(term, page: request), offset: offset)
        } catch {
            throw normalize(error)
        }
    }

    func collections() async throws -> [MediaCollection] {
        do { return try await provider.collections() } catch { throw normalize(error) }
    }

    func resume(query: MediaQuery) async throws -> MediaPage {
        do {
            let shelf = try await provider.playbackShelf(limit: query.limit)
            let values = shelf.resume.map { item in
                MediaSummary(
                    id: item.mediaID,
                    kind: item.item.kind == .movie ? .movie : .series,
                    title: item.title,
                    durationSeconds: item.durationSeconds,
                    posterURL: item.posterURL,
                    userState: item.userState
                )
            }
            return MediaPage(
                items: values.map {
                    LocatedMediaItem(
                        locator: MediaLocatorID(sourceID: sourceID, providerItemID: $0.id),
                        summary: $0
                    )
                },
                nextCursor: nil,
                total: values.count
            )
        } catch { throw normalize(error) }
    }

    func detail(locator: MediaLocatorID, summary: MediaSummary) async throws -> MediaDetail {
        do {
            return try await provider.detail(for: summary)
        } catch { throw normalize(error) }
    }

    func seasons(series: MediaLocatorID) async throws -> [Season] {
        do { return try await provider.seasons(seriesID: series.providerItemID) }
        catch { throw normalize(error) }
    }

    func episodes(
        series: MediaLocatorID,
        seasonID: String,
        page: PageRequest
    ) async throws -> Page<Episode> {
        do {
            return try await provider.episodes(
                seriesID: series.providerItemID,
                seasonID: seasonID,
                page: page
            )
        } catch { throw normalize(error) }
    }

    func person(id: String) async throws -> PersonDetail {
        do { return try await provider.person(id: id) } catch { throw normalize(error) }
    }

    func works(personID: String, query: MediaQuery) async throws -> MediaPage {
        let offset = query.cursor.flatMap { Int($0.rawValue) } ?? 0
        do {
            return map(
                try await provider.works(
                    forPersonID: personID,
                    page: PageRequest(number: (offset / query.limit) + 1, size: query.limit),
                    sort: query.sort
                ),
                offset: offset
            )
        } catch { throw normalize(error) }
    }

    func playback(locator: MediaLocatorID) async throws -> SourcePlaybackDescriptor {
        let asset = try await firstAsset(locator)
        let url = try await provider.playbackURL(for: asset)
        return SourcePlaybackDescriptor(url: url, mode: .directPlay, mediaSourceID: asset.id)
    }

    func download(locator: MediaLocatorID) async throws -> SourcePlaybackDescriptor {
        let asset = try await firstAsset(locator)
        let url = try await provider.downloadURL(for: asset)
        return SourcePlaybackDescriptor(url: url, mode: .directPlay, mediaSourceID: asset.id)
    }

    func report(_ event: PlaybackEvent) async throws {
        let locator: MediaLocatorID
        let position: Double
        let isStopped: Bool
        switch event {
        case let .started(value, seconds), let .progress(value, seconds, _):
            locator = value
            position = seconds
            isStopped = false
        case let .stopped(value, seconds, _):
            locator = value
            position = seconds
            isStopped = true
        }
        let asset = try await firstAsset(locator)
        let update = PlaybackUpdate(
            item: PlayableItem(id: locator.providerItemID, kind: asset.mediaKind),
            assetID: asset.id,
            positionSeconds: position
        )
        if isStopped {
            _ = try await provider.reportStopped(update)
        } else {
            _ = try await provider.reportProgress(update)
        }
    }

    private func firstAsset(_ locator: MediaLocatorID) async throws -> MediaAsset {
        if let asset = selectedAssets[locator.providerItemID] { return asset }
        let assets = try await provider.assets(
            for: PlayableItem(id: locator.providerItemID, kind: .movie)
        )
        guard let asset = assets.first else {
            throw MediaSourceFailure.unsupported("No playable UHDNow media asset")
        }
        selectedAssets[locator.providerItemID] = asset
        return asset
    }

    private func map(_ page: Page<MediaSummary>, offset: Int) -> MediaPage {
        let items = page.items.map {
            LocatedMediaItem(
                locator: MediaLocatorID(sourceID: sourceID, providerItemID: $0.id),
                summary: $0
            )
        }
        let nextOffset = offset + items.count
        return MediaPage(
            items: items,
            nextCursor: nextOffset < page.total ? MediaCursor(rawValue: String(nextOffset)) : nil,
            total: page.total
        )
    }

    private func normalize(_ error: Error) -> Error {
        if error is CancellationError { return CancellationError() }
        if let error = error as? ProviderError {
            switch error {
            case .unauthenticated, .invalidCredentials, .sessionExpired, .forbidden:
                return MediaSourceFailure.unauthorized
            case .invalidResponse: return MediaSourceFailure.invalidResponse
            case .unavailable: return MediaSourceFailure.unavailable
            default: return MediaSourceFailure.transport(String(describing: error))
            }
        }
        return MediaSourceFailure.transport(String(describing: error))
    }
}

private extension MediaAsset {
    var mediaKind: PlayableKind {
        episodeID == nil ? .movie : .episode
    }
}
