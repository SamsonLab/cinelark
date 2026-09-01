import Foundation
import Testing
import CineLarkDomain
import CineLarkPluginAPI
@testable import CineLarkEmby

private actor RequestRecorder {
    private(set) var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
}

private actor AttemptCounter {
    private var value = 0

    func next() -> Int {
        defer { value += 1 }
        return value
    }
}

private actor SuspendedRequestRecorder {
    private(set) var paths: [String] = []
    private var releases: [CheckedContinuation<Void, Never>] = []
    private var arrivals: [(Int, CheckedContinuation<Void, Never>)] = []

    func recordAndSuspend(_ request: URLRequest) async {
        paths.append(request.url!.path)
        let count = paths.count
        let ready = arrivals.filter { $0.0 <= count }
        arrivals.removeAll { $0.0 <= count }
        ready.forEach { $0.1.resume() }
        await withCheckedContinuation { continuation in
            releases.append(continuation)
        }
    }

    func waitForCount(_ count: Int) async {
        guard paths.count < count else { return }
        await withCheckedContinuation { continuation in
            arrivals.append((count, continuation))
        }
    }

    func releaseNext() {
        releases.removeFirst().resume()
    }
}

private func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

private func response(for request: URLRequest, status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func response(
    for request: URLRequest,
    status: Int,
    headers: [String: String]
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
    )!
}

@Test func descriptorAdvertisesOnlyImplementedAuthentication() {
    let factory = EmbyPluginFactory(
        device: EmbyDeviceIdentity(id: "stable-device", appVersion: "1.0")
    )

    #expect(factory.descriptor.authenticationModes == [.usernamePassword])
}

@Test func validationPreservesReverseProxyBasePath() async throws {
    let recorder = RequestRecorder()
    let http = EmbyHTTPClient { request in
        await recorder.append(request)
        return HTTPResponse(
            data: Data(#"{"Id":"server-1","ServerName":"Living Room"}"#.utf8),
            response: response(for: request)
        )
    }
    let factory = EmbyPluginFactory(
        device: EmbyDeviceIdentity(id: "stable-device", appVersion: "1.0"),
        http: http
    )

    let identity = try await factory.validate(baseURL: URL(string: "https://example.com/media/emby")!)

    #expect(identity.serverID == "server-1")
    let requests = await recorder.requests
    #expect(requests.first?.url?.path == "/media/emby/System/Info/Public")
    #expect(requests.first?.value(forHTTPHeaderField: "X-Emby-Authorization")?.contains("DeviceId=\"stable-device\"") == true)
}

@Test func mutationFailuresMapStatusAndBoundedRetryAfterWithoutResponseData() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let rateLimited = EmbyHTTPClient { request in
        HTTPResponse(
            data: Data("private provider response".utf8),
            response: response(
                for: request,
                status: 429,
                headers: ["Retry-After": "99999"]
            )
        )
    }
    let rateLimitedRuntime = try await makeRuntime(sourceID: sourceID, http: rateLimited)
    let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "movie-1")

    await #expect(throws: MediaSourceFailure.rateLimited(retryAfterSeconds: 3_600)) {
        try await rateLimitedRuntime.remoteStateMirror!.mirrorState(
            "user-1",
            .favorite(locator, true)
        )
    }

    let rejected = EmbyHTTPClient { request in
        HTTPResponse(
            data: Data("credential-bearing diagnostic".utf8),
            response: response(for: request, status: 400)
        )
    }
    let rejectedRuntime = try await makeRuntime(sourceID: sourceID, http: rejected)
    await #expect(throws: MediaSourceFailure.requestRejected) {
        try await rejectedRuntime.remoteStateMirror!.mirrorState(
            "user-1",
            .favorite(locator, true)
        )
    }
}

@Test func responseValidationSeparatesAuthenticationAndTransientServiceFailure() {
    let request = URLRequest(url: URL(string: "https://example.test/emby")!)
    #expect(throws: MediaSourceFailure.unauthorized) {
        try EmbyResponseValidator.validate(response(for: request, status: 401))
    }
    #expect(throws: MediaSourceFailure.unavailable) {
        try EmbyResponseValidator.validate(response(for: request, status: 503))
    }
}

@Test func playbackCheckInsRemainOrderedAcrossSuspendedHTTPRequests() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let recorder = SuspendedRequestRecorder()
    let http = EmbyHTTPClient { request in
        await recorder.recordAndSuspend(request)
        return HTTPResponse(data: Data(), response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)
    let session = try #require(runtime.playbackSession)
    let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "movie-1")

    let started = Task {
        try await session.report(.started(locator: locator, positionSeconds: 0))
    }
    await recorder.waitForCount(1)
    let progress = Task {
        try await session.report(.progress(
            locator: locator,
            positionSeconds: 12,
            isPaused: false
        ))
    }
    let stopped = Task {
        try await session.report(.stopped(
            locator: locator,
            positionSeconds: 20,
            reachedEOF: false
        ))
    }
    for _ in 0..<20 { await Task.yield() }

    var paths = await recorder.paths
    #expect(paths == ["/emby/Sessions/Playing"])

    await recorder.releaseNext()
    await recorder.waitForCount(2)
    paths = await recorder.paths
    #expect(paths == [
        "/emby/Sessions/Playing",
        "/emby/Sessions/Playing/Progress"
    ])

    await recorder.releaseNext()
    await recorder.waitForCount(3)
    paths = await recorder.paths
    #expect(paths == [
        "/emby/Sessions/Playing",
        "/emby/Sessions/Playing/Progress",
        "/emby/Sessions/Playing/Stopped"
    ])
    await recorder.releaseNext()

    try await started.value
    try await progress.value
    try await stopped.value
}

@Test func legacyUHDNowSourceProducesAnExplicitCanonicalReconnectProposal() {
    let sourceID = SourceID(rawValue: UUID())
    let legacyID = EmbyPluginFactory.legacyUHDNowPluginID
    let factory = EmbyPluginFactory(
        device: EmbyDeviceIdentity(id: "stable-device", appVersion: "1.0")
    )
    let configuration = SourceConfiguration(
        sourceID: sourceID,
        baseURL: URL(string: "https://www.uhdnow.com/api/v1")!,
        serverIdentity: SourceInstanceIdentity(
            pluginID: legacyID,
            serverID: "www.uhdnow.com/api/v1"
        ),
        displayName: "Living Room"
    )

    let proposal = factory.migrationProposal(
        from: legacyID,
        configuration: configuration
    )

    #expect(factory.legacyPluginIDs == [legacyID])
    #expect(proposal?.sourceID == sourceID)
    #expect(proposal?.legacyPluginID == legacyID)
    #expect(proposal?.targetPluginID == EmbyPluginFactory.pluginID)
    #expect(proposal?.suggestedBaseURL.absoluteString == "https://www.uhdnow.com")
    #expect(proposal?.displayName == "Living Room")
}

@Test func offsetCursorMapsToEmbyStartIndexWithoutPuttingTokenInURL() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let recorder = RequestRecorder()
    let http = EmbyHTTPClient { request in
        await recorder.append(request)
        let json = #"{"Items":[{"Id":"movie-1","Name":"Arrival","Type":"Movie"}],"TotalRecordCount":3}"#
        return HTTPResponse(data: Data(json.utf8), response: response(for: request))
    }
    let vault = EmbyTokenVault(
        load: { _ in "secret-token" },
        save: { _, _ in },
        remove: { _ in }
    )
    let factory = EmbyPluginFactory(
        device: EmbyDeviceIdentity(id: "device", appVersion: "1.0"),
        http: http,
        tokenVault: vault
    )
    let configuration = SourceConfiguration(
        sourceID: sourceID,
        baseURL: URL(string: "https://example.com/emby")!,
        serverIdentity: SourceInstanceIdentity(pluginID: EmbyPluginFactory.pluginID, serverID: "server"),
        displayName: "Emby",
        remoteUserID: "user-1"
    )
    let runtime = try await factory.makeRuntime(configuration: configuration)
    let page = try await runtime.browse!.page(
        MediaQuery(
            scope: SourceScope(sourceID: sourceID),
            kinds: [.movie],
            cursor: MediaCursor(rawValue: "1"),
            limit: 1
        )
    )

    #expect(page.nextCursor == MediaCursor(rawValue: "2"))
    let request = await recorder.requests.first!
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
    #expect(components.queryItems?.contains(URLQueryItem(name: "StartIndex", value: "1")) == true)
    #expect(request.url?.absoluteString.contains("secret-token") == false)
    #expect(request.value(forHTTPHeaderField: "X-Emby-Authorization")?.contains("secret-token") == true)
}

@Test func resumeFixturePreservesEpisodeIdentityAndAdvancesByRawItems() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let data = try fixtureData("resume-page")
    let http = EmbyHTTPClient { request in
        HTTPResponse(data: data, response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)

    let page = try await runtime.hierarchy!.resume(
        MediaQuery(scope: SourceScope(sourceID: sourceID), limit: 3)
    )

    #expect(runtime.descriptor.capabilities.itemKinds.contains(.episode))
    #expect(page.items.map(\.summary.kind) == [.episode, .episode, .movie])
    #expect(page.items.map(\.locator.providerItemID) == [
        "episode-synthetic-1",
        "episode-synthetic-2",
        "movie-synthetic-1"
    ])
    #expect(page.nextCursor == MediaCursor(rawValue: "3"))
    #expect(page.total == 7)
}

@Test func metadataFixtureNormalizesSummaryFieldsAndRequestsThemExplicitly() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let recorder = RequestRecorder()
    let data = try fixtureData("metadata-items")
    let http = EmbyHTTPClient { request in
        await recorder.append(request)
        return HTTPResponse(data: data, response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)

    let page = try await runtime.browse!.page(
        MediaQuery(scope: SourceScope(sourceID: sourceID), limit: 20)
    )
    let series = try #require(page.items.first?.summary)
    let movie = try #require(page.items.last?.summary)

    #expect(series.originalTitle == "Synthetic Original Series")
    #expect(series.totalSeasons == 4)
    #expect(series.genres.map(\.name) == ["Drama", "Science Fiction"])
    #expect(series.genres.map(\.slug) == ["drama", "science-fiction"])
    #expect(series.userState.lastPlayedAt?.timeIntervalSince1970 == 1_787_753_106.1234567)
    #expect(movie.originalTitle == "Synthetic Original Movie")
    #expect(movie.totalSeasons == nil)
    #expect(movie.genres.first?.id == series.genres.first?.id)
    #expect(movie.userState.lastPlayedAt == Date(timeIntervalSince1970: 1_787_627_045))

    let request = try #require(await recorder.requests.first)
    let fields = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first(where: { $0.name == "Fields" })?
        .value?
        .split(separator: ",")
        .map(String.init) ?? []
    #expect(fields.contains("OriginalTitle"))
    #expect(fields.contains("Genres"))
}

@Test func remoteImportRejectsAProviderThatCannotAdvanceItsCursor() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let attempts = AttemptCounter()
    let http = EmbyHTTPClient { request in
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let isResume = request.url?.path.hasSuffix("/Items/Resume") == true
        let json: String

        if !isResume {
            json = #"{"Items":[],"TotalRecordCount":0}"#
        } else if await attempts.next() == 0 {
            json = #"{"Items":[{"Id":"folder-synthetic-1","Name":"Unsupported","Type":"Folder"}],"TotalRecordCount":3}"#
        } else if components?.queryItems?.contains(
            URLQueryItem(name: "StartIndex", value: "1")
        ) == true {
            json = #"{"Items":[],"TotalRecordCount":3}"#
        } else {
            return HTTPResponse(data: Data(), response: response(for: request, status: 503))
        }
        return HTTPResponse(data: Data(json.utf8), response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)

    do {
        _ = try await runtime.remoteStateImport!.importState()
        Issue.record("Expected a non-advancing Emby cursor to be rejected")
    } catch let failure as MediaSourceFailure {
        #expect(failure == .invalidResponse)
    }
}

@Test func discoveryParsesAddressAndDeduplicatesThroughFactoryClient() async throws {
    let payload = Data(
        #"{"Address":"192.168.1.20:8096/emby","Id":"server-1","Name":"Living Room"}"#.utf8
    )
    let parsed = EmbyDiscoveryParser.parse(payload)
    #expect(parsed?.address.absoluteString == "http://192.168.1.20:8096/emby")
    #expect(parsed?.serverID == "server-1")

    let expected = [parsed!]
    let factory = EmbyPluginFactory(
        device: EmbyDeviceIdentity(id: "device", appVersion: "1.0"),
        discovery: EmbyDiscoveryClient { timeout in
            #expect(timeout == .seconds(2))
            return expected
        }
    )
    #expect(try await factory.discover() == expected)
}

@Test func hierarchyAndPlaybackMapEmbyContentWithoutSecretsInURLs() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let recorder = RequestRecorder()
    let http = EmbyHTTPClient { request in
        await recorder.append(request)
        let path = request.url!.path
        let json: String
        switch path {
        case "/emby/Users/user-1/Views":
            json = #"{"Items":[{"Id":"movies","Name":"Movies","Type":"CollectionFolder","CollectionType":"movies","ChildCount":12}],"TotalRecordCount":1}"#
        case "/emby/Users/user-1/Items/movie-1":
            json = #"{"Id":"movie-1","Name":"Arrival","Type":"Movie","Overview":"First contact","ProviderIds":{"Tmdb":"329865","Imdb":"tt2543164"},"People":[{"Id":"director-1","Name":"Denis Villeneuve","Type":"Director"},{"Id":"actor-1","Name":"Amy Adams","Role":"Louise","Type":"Actor"}]}"#
        case "/emby/Shows/series-1/Seasons":
            json = #"{"Items":[{"Id":"season-1","Name":"Season 1","Type":"Season","IndexNumber":1,"ChildCount":8}],"TotalRecordCount":1}"#
        case "/emby/Shows/series-1/Episodes":
            json = #"{"Items":[{"Id":"episode-1","Name":"Pilot","Type":"Episode","SeriesId":"series-1","SeasonId":"season-1","IndexNumber":1,"RunTimeTicks":36000000000}],"TotalRecordCount":1}"#
        case "/emby/Users/user-1/Items/Resume":
            json = #"{"Items":[{"Id":"episode-4","Name":"Continue","Type":"Episode","SeriesId":"series-1","SeasonId":"season-2","ParentIndexNumber":2,"IndexNumber":4,"RunTimeTicks":36000000000,"UserData":{"PlaybackPositionTicks":9000000000}}],"TotalRecordCount":1}"#
        case "/emby/Shows/NextUp":
            json = #"{"Items":[{"Id":"episode-5","Name":"Next","Type":"Episode","SeriesId":"series-1","SeasonId":"season-2","ParentIndexNumber":2,"IndexNumber":5,"RunTimeTicks":36000000000}],"TotalRecordCount":1}"#
        case "/emby/Items/movie-1/PlaybackInfo":
            json = #"{"MediaSources":[{"Id":"source-1","SupportsDirectPlay":true,"SupportsDirectStream":true}]}"#
        default:
            Issue.record("Unexpected Emby path: \(path)")
            json = "{}"
        }
        return HTTPResponse(data: Data(json.utf8), response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)
    let hierarchy = runtime.hierarchy!

    let collections = try await hierarchy.collections()
    #expect(collections.first?.mediaKind == .movie)
    #expect(collections.first?.itemCount == 12)

    let movie = MediaLocatorID(sourceID: sourceID, providerItemID: "movie-1")
    let detail = try await hierarchy.detail(
        movie,
        MediaSummary(id: "movie-1", kind: .movie, title: "Arrival")
    )
    #expect(detail.tmdbID == "329865")
    #expect(detail.directors.first?.name == "Denis Villeneuve")
    #expect(detail.cast.first?.character == "Louise")

    let series = MediaLocatorID(sourceID: sourceID, providerItemID: "series-1")
    #expect(try await hierarchy.seasons(series).first?.number == 1)
    #expect(try await hierarchy.episodes(series, "season-1", PageRequest(number: 1, size: 20)).items.first?.durationSeconds == 3_600)
    let seriesPlayback = try await hierarchy.seriesPlayback(series)
    #expect(seriesPlayback.resumableItem?.item.id == "episode-4")
    #expect(seriesPlayback.resumableItem?.seasonNumber == 2)
    #expect(seriesPlayback.resumableItem?.episodeNumber == 4)
    #expect(seriesPlayback.resumableItem?.userState.positionSeconds == 900)
    #expect(seriesPlayback.nextUp?.item.id == "episode-5")

    let descriptor = try await runtime.playback!.resolve(movie)
    #expect(descriptor.mode == .directPlay)
    #expect(descriptor.url.path == "/emby/Videos/movie-1/stream")
    #expect(descriptor.url.query?.contains("static=true") == true)
    #expect(descriptor.url.query?.contains("MediaSourceId=source-1") == true)
    #expect(descriptor.url.absoluteString.contains("secret-token") == false)
    #expect(descriptor.headers["X-Emby-Token"] == "secret-token")
}

@Test func playbackVariantsPreserveEveryEmbyMediaSourceAndResolveTheSelection() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let http = EmbyHTTPClient { request in
        let json = #"{"MediaSources":[{"Id":"source-1080p","Name":"1080p AVC","Container":"mkv","Size":1000,"RunTimeTicks":72000000000,"Bitrate":8000000,"DirectStreamUrl":"Videos/movie-1/stream?MediaSourceId=source-1080p","SupportsDirectPlay":true,"MediaStreams":[{"Index":0,"Type":"Video","Codec":"h264","Profile":"High","BitRate":7000000,"Width":1920,"Height":1080,"RealFrameRate":23.976,"PixelFormat":"yuv420p","VideoRange":"SDR"},{"Index":1,"Type":"Audio","Codec":"aac","Channels":2,"Language":"eng","DisplayTitle":"English AAC","IsDefault":true}]},{"Id":"source-4k","Name":"4K HEVC","Container":"mkv","Size":2000,"RunTimeTicks":72000000000,"Bitrate":20000000,"DirectStreamUrl":"Videos/movie-1/stream?MediaSourceId=source-4k","SupportsDirectStream":true,"MediaStreams":[{"Index":0,"Type":"Video","Codec":"hevc","Profile":"Main 10","BitRate":18000000,"Width":3840,"Height":2160,"RealFrameRate":24,"PixelFormat":"yuv420p10le","VideoRange":"HDR10"},{"Index":2,"Type":"Subtitle","Codec":"ass","Language":"zho","DisplayTitle":"Chinese","IsDefault":true}]}]}"#
        return HTTPResponse(data: Data(json.utf8), response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)
    let playback = try #require(runtime.playback)
    let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "movie-1")

    let variants = try await playback.variants(locator)

    #expect(variants.map(\.id) == ["source-1080p", "source-4k"])
    #expect(variants.first?.isPreferred == true)
    #expect(variants.first?.audioTracks.first?.title == "English AAC")
    #expect(variants.last?.width == 3_840)
    #expect(variants.last?.height == 2_160)
    #expect(variants.last?.videoCodec == "hevc")
    #expect(variants.last?.videoRange == "HDR10")
    #expect(variants.last?.subtitleTracks.first?.title == "Chinese")

    let descriptor = try await playback.resolveVariant(locator, "source-4k")
    #expect(descriptor.mediaSourceID == "source-4k")
    #expect(descriptor.url.query?.contains("MediaSourceId=source-4k") == true)
}

@Test func playbackFixturePreservesTheProviderIssuedQueryCapability() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let data = try fixtureData("playback-info")
    let http = EmbyHTTPClient { request in
        HTTPResponse(data: data, response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)

    let descriptor = try await runtime.playback!.resolve(
        MediaLocatorID(sourceID: sourceID, providerItemID: "movie-synthetic-1")
    )
    let components = try #require(
        URLComponents(url: descriptor.url, resolvingAgainstBaseURL: false)
    )

    #expect(descriptor.url.scheme == "https")
    #expect(descriptor.url.host == "example.com")
    #expect(descriptor.url.path == "/play/synthetic/stream")
    #expect(components.queryItems == [
        URLQueryItem(name: "MediaSourceId", value: "source-synthetic-1"),
        URLQueryItem(name: "api_key", value: "fixture-secret")
    ])
    #expect(descriptor.url.absoluteString.contains("secret-token") == false)
    #expect(descriptor.headers["X-Emby-Token"] == "secret-token")
    #expect(descriptor.mode == .directStream)
}

@Test func playbackRejectsCrossOriginDirectStreamBeforeForwardingAuthorization() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let http = EmbyHTTPClient { request in
        let json = #"{"MediaSources":[{"Id":"source-synthetic-1","DirectStreamUrl":"https://cdn.invalid/play/stream","SupportsDirectStream":true}]}"#
        return HTTPResponse(data: Data(json.utf8), response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)

    await #expect(throws: MediaSourceFailure.self) {
        _ = try await runtime.playback!.resolve(
            MediaLocatorID(sourceID: sourceID, providerItemID: "movie-synthetic-1")
        )
    }
}

@Test func playbackPreservesAProviderCapabilityOnAnAbsoluteSameOriginStream() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let http = EmbyHTTPClient { request in
        let json = #"{"MediaSources":[{"Id":"source-synthetic-1","DirectStreamUrl":"https://example.com/play/stream?api_key=fixture-secret&MediaSourceId=source-synthetic-1","SupportsDirectStream":true}]}"#
        return HTTPResponse(data: Data(json.utf8), response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)

    let descriptor = try await runtime.playback!.resolve(
        MediaLocatorID(sourceID: sourceID, providerItemID: "movie-synthetic-1")
    )

    #expect(
        descriptor.url.absoluteString ==
            "https://example.com/play/stream?api_key=fixture-secret&MediaSourceId=source-synthetic-1"
    )
    #expect(descriptor.headers["X-Emby-Token"] == "secret-token")
}

@Test func playbackPreservesSameOriginStreamTokenAndAlsoForwardsAuthorization() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let http = EmbyHTTPClient { request in
        let json = #"{"MediaSources":[{"Id":"source-synthetic-1","DirectStreamUrl":"/play/video/asset-1?token=stream-token&MediaSourceId=source-synthetic-1","SupportsDirectStream":true}]}"#
        return HTTPResponse(data: Data(json.utf8), response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)

    let descriptor = try await runtime.playback!.resolve(
        MediaLocatorID(sourceID: sourceID, providerItemID: "movie-synthetic-1")
    )

    #expect(
        descriptor.url.absoluteString ==
            "https://example.com/play/video/asset-1?token=stream-token&MediaSourceId=source-synthetic-1"
    )
    #expect(descriptor.headers["Authorization"] == "stream-token")
    #expect(descriptor.headers["X-Emby-Token"] == "secret-token")
}

@Test func directPlayPreservesAProviderIssuedQueryCapability() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let http = EmbyHTTPClient { request in
        let json = #"{"MediaSources":[{"Id":"source-synthetic-1","DirectStreamUrl":"/play/video/asset-1?api_key=secret-token","SupportsDirectPlay":true,"SupportsDirectStream":true}]}"#
        return HTTPResponse(data: Data(json.utf8), response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)

    let descriptor = try await runtime.playback!.resolve(
        MediaLocatorID(sourceID: sourceID, providerItemID: "movie-synthetic-1")
    )

    let components = try #require(
        URLComponents(url: descriptor.url, resolvingAgainstBaseURL: false)
    )
    #expect(descriptor.url.path == "/play/video/asset-1")
    #expect(components.queryItems == [
        URLQueryItem(name: "api_key", value: "secret-token")
    ])
    #expect(descriptor.headers == ["X-Emby-Token": "secret-token"])
    #expect(descriptor.mode == .directPlay)
    #expect(descriptor.mediaSourceID == "source-synthetic-1")
}

@Test func remoteStateImportAndMirrorUseExplicitUserAndMutationEndpoints() async throws {
    let sourceID = SourceID(rawValue: UUID())
    let recorder = RequestRecorder()
    let http = EmbyHTTPClient { request in
        await recorder.append(request)
        let path = request.url!.path
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let isFavoriteQuery = components?.queryItems?.contains(
            URLQueryItem(name: "IsFavorite", value: "true")
        ) == true
        let json: String
        if path == "/emby/Users/user-1/Items", isFavoriteQuery {
            json = #"{"Items":[{"Id":"movie-1","Name":"Arrival","Type":"Movie","UserData":{"IsFavorite":true}}],"TotalRecordCount":1}"#
        } else if path == "/emby/Users/user-1/Items/Resume" {
            json = #"{"Items":[{"Id":"movie-1","Name":"Arrival","Type":"Movie","RunTimeTicks":1000000000,"UserData":{"PlaybackPositionTicks":250000000}},{"Id":"episode-1","Name":"Synthetic Episode","Type":"Episode","RunTimeTicks":2000000000,"UserData":{"PlaybackPositionTicks":500000000}}],"TotalRecordCount":2}"#
        } else {
            json = "{}"
        }
        return HTTPResponse(data: Data(json.utf8), response: response(for: request))
    }
    let runtime = try await makeRuntime(sourceID: sourceID, http: http)
    let snapshot = try await runtime.remoteStateImport!.importState()

    #expect(snapshot.marker == "emby-v1:server:user-1")
    #expect(snapshot.items.count == 2)
    let states = Dictionary(uniqueKeysWithValues: snapshot.items.map {
        ($0.locator.providerItemID, $0)
    })
    #expect(states["movie-1"]?.isFavorite == true)
    #expect(states["movie-1"]?.playback?.positionSeconds == 25)
    #expect(states["episode-1"]?.summary.kind == .episode)
    #expect(states["episode-1"]?.playback?.positionSeconds == 50)

    let locator = MediaLocatorID(sourceID: sourceID, providerItemID: "movie-1")
    try await runtime.remoteStateMirror!.mirrorState(
        "user-1",
        .favorite(locator, false)
    )
    try await runtime.remoteStateMirror!.mirrorState(
        "user-1",
        .playback(locator, UserPlaybackState(
            played: true,
            positionSeconds: 0,
            progress: 1
        ))
    )

    let requests = await recorder.requests
    #expect(requests.contains {
        $0.url?.path == "/emby/Users/user-1/FavoriteItems/movie-1" && $0.httpMethod == "DELETE"
    })
    #expect(requests.contains {
        $0.url?.path == "/emby/Sessions/Playing/Progress" && $0.httpMethod == "POST"
    })
    #expect(requests.contains {
        $0.url?.path == "/emby/Users/user-1/PlayedItems/movie-1" && $0.httpMethod == "POST"
    })

    await #expect(throws: MediaSourceFailure.self) {
        try await runtime.remoteStateMirror!.mirrorState(
            "different-user",
            .favorite(locator, true)
        )
    }
}

private func makeRuntime(
    sourceID: SourceID,
    http: EmbyHTTPClient
) async throws -> MediaSourceRuntime {
    let vault = EmbyTokenVault(
        load: { _ in "secret-token" },
        save: { _, _ in },
        remove: { _ in }
    )
    let factory = EmbyPluginFactory(
        device: EmbyDeviceIdentity(id: "device", appVersion: "1.0"),
        http: http,
        tokenVault: vault
    )
    return try await factory.makeRuntime(configuration: SourceConfiguration(
        sourceID: sourceID,
        baseURL: URL(string: "https://example.com/emby")!,
        serverIdentity: SourceInstanceIdentity(
            pluginID: EmbyPluginFactory.pluginID,
            serverID: "server"
        ),
        displayName: "Emby",
        remoteUserID: "user-1"
    ))
}
