import Foundation
import Testing
import CineLarkDomain
@testable import CineLarkUHDNow

@Suite("UHDNow provider")
struct UHDNowProviderTests {
    @Test("login stores the issued raw token without authorizing the login request")
    func loginStoresSession() async throws {
        let transport = StubTransport([
            .json("""
            {
              "ok": true,
              "data": {
                "token": "synthetic-token",
                "expires_at": "2099-08-20T03:09:00Z"
              }
            }
            """)
        ])
        let store = MemorySessionStore()
        let provider = UHDNowProvider(
            configuration: .production,
            sessionStore: store,
            transport: transport
        )

        let session = try await provider.signIn(
            credentials: ProviderCredentials(
                username: "synthetic-user",
                password: "synthetic-password",
                totpCode: nil
            )
        )

        #expect(session.token == "synthetic-token")
        let storedSession = try await store.load()
        #expect(storedSession == session)

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/api/v1/auth/login")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

        let body = try #require(request.httpBody)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        #expect(object["username"] == "synthetic-user")
        #expect(object["password"] == "synthetic-password")
        #expect(object["totp_code"] == "")
    }

    @Test("rejected login credentials do not create a session")
    func rejectedLoginDoesNotCreateSession() async throws {
        let transport = StubTransport([
            HTTPResult(data: Data("{}".utf8), statusCode: 401)
        ])
        let store = MemorySessionStore()
        let provider = UHDNowProvider(
            configuration: .production,
            sessionStore: store,
            transport: transport
        )

        do {
            _ = try await provider.signIn(
                credentials: ProviderCredentials(
                    username: "synthetic-user",
                    password: "incorrect-synthetic-password",
                    totpCode: nil
                )
            )
            Issue.record("Expected login to reject the credentials.")
        } catch let error as ProviderError {
            #expect(error == .invalidCredentials)
        }

        let storedSession = try await store.load()
        #expect(storedSession == nil)
    }

    @Test("authenticated requests send the issued token without a Bearer prefix")
    func authenticatedRequestUsesRawToken() async throws {
        let session = ProviderSession(
            token: "synthetic-token",
            expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
        )
        let store = MemorySessionStore(session: session)
        let transport = StubTransport([
            .json("""
            {
              "ok": true,
              "data": {
                "page": 1,
                "page_size": 20,
                "total": 1,
                "items": [{
                  "id": "media-synthetic",
                  "type": "movie",
                  "title": "Synthetic Feature",
                  "origin_title": "Synthetic Feature",
                  "release_year": 2026,
                  "rating": 84,
                  "poster_path": "/img/i/poster/poster-synthetic",
                  "genres": [],
                  "user_state": {
                    "played": false,
                    "position_ticks": 50000000,
                    "progress_pct": 5
                  }
                }]
              }
            }
            """)
        ])
        let provider = UHDNowProvider(
            configuration: .production,
            sessionStore: store,
            transport: transport
        )

        _ = try await provider.restoreSession()
        let page = try await provider.hot(page: PageRequest(number: 1, size: 20))

        #expect(page.items.first?.title == "Synthetic Feature")
        #expect(page.items.first?.rating == 8.4)
        #expect(page.items.first?.userState.positionSeconds == 5)
        #expect(page.items.first?.userState.progress == 0.05)

        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "synthetic-token")
        #expect(request.url?.query?.contains("page=1") == true)
        #expect(request.url?.query?.contains("page_size=20") == true)
    }

    @Test("playback URL combines the resolved domain, asset path, and token")
    func buildsTokenizedPlaybackURL() async throws {
        let session = ProviderSession(
            token: "synthetic-token",
            expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
        )
        let store = MemorySessionStore(session: session)
        let transport = StubTransport([
            .json("""
            {
              "ok": true,
              "data": [{
                "id": "domain-synthetic",
                "name": "Synthetic VOD",
                "description": "Synthetic fixture",
                "domain": "https://placeholder.invalid",
                "normalized_host": "placeholder.invalid",
                "sort_order": 1
              }]
            }
            """),
            .json("""
            {
              "ok": true,
              "data": {
                "id": "domain-synthetic",
                "name": "Synthetic VOD",
                "domain": "https://media.example",
                "normalized_host": "media.example",
                "parent_id": "parent-synthetic",
                "sort_order": 1
              }
            }
            """)
        ])
        let provider = UHDNowProvider(
            configuration: .production,
            sessionStore: store,
            transport: transport
        )
        _ = try await provider.restoreSession()

        let url = try await provider.playbackURL(
            for: MediaAsset(
                id: "asset-synthetic",
                mediaID: "media-synthetic",
                displayName: "Synthetic 4K",
                playPath: "/play/video/asset-synthetic",
                downloadPath: "/download/video/asset-synthetic"
            )
        )
        let downloadURL = try await provider.downloadURL(
            for: MediaAsset(
                id: "asset-synthetic",
                mediaID: "media-synthetic",
                displayName: "Synthetic 4K",
                playPath: "/play/video/asset-synthetic",
                downloadPath: "/download/video/asset-synthetic"
            )
        )

        #expect(url.scheme == "https")
        #expect(url.host == "media.example")
        #expect(url.path == "/play/video/asset-synthetic")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems == [URLQueryItem(name: "token", value: "synthetic-token")])
        #expect(downloadURL.host == "media.example")
        #expect(downloadURL.path == "/download/video/asset-synthetic")
        let downloadComponents = try #require(
            URLComponents(url: downloadURL, resolvingAgainstBaseURL: false)
        )
        #expect(
            downloadComponents.queryItems == [
                URLQueryItem(name: "token", value: "synthetic-token")
            ]
        )
    }

    @Test("asset responses retain version and download metadata")
    func assetVersionMetadata() async throws {
        let session = ProviderSession(
            token: "synthetic-token",
            expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
        )
        let transport = StubTransport([
            .json("""
            {
              "ok": true,
              "data": {
                "videos": [{
                  "asset_id": "asset-synthetic",
                  "media_id": "media-synthetic",
                  "name": "4K SDR HEVC",
                  "display_name": "4K SDR HEVC",
                  "container": "mkv",
                  "duration": 2760,
                  "file_size": 2147483648,
                  "bit_rate": 5800000,
                  "width": 3840,
                  "height": 2160,
                  "resolution": "2160p",
                  "encoding": "hevc",
                  "profile": "Main 10",
                  "video_bit_rate": 5600000,
                  "pix_fmt": "yuv420p10le",
                  "frame_rate": "25",
                  "video_range": "SDR",
                  "audio_tracks": [],
                  "subtitle_tracks": [],
                  "play_path": "/play/video/asset-synthetic",
                  "download_path": "/download/video/asset-synthetic"
                }],
                "subtitles": []
              }
            }
            """)
        ])
        let provider = UHDNowProvider(
            sessionStore: MemorySessionStore(session: session),
            transport: transport
        )
        _ = try await provider.restoreSession()

        let assets = try await provider.assets(
            for: PlayableItem(id: "episode-synthetic", kind: .episode)
        )
        let asset = try #require(assets.first)
        #expect(asset.displayName == "4K SDR HEVC")
        #expect(asset.width == 3840)
        #expect(asset.height == 2160)
        #expect(asset.profile == "Main 10")
        #expect(asset.downloadPath == "/download/video/asset-synthetic")
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/api/v1/stream/episodes/episode-synthetic/assets")
    }

    @Test("an unauthorized response clears the stored session")
    func unauthorizedResponseClearsSession() async throws {
        let session = ProviderSession(
            token: "synthetic-token",
            expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
        )
        let store = MemorySessionStore(session: session)
        let transport = StubTransport([
            HTTPResult(data: Data("{}".utf8), statusCode: 401)
        ])
        let provider = UHDNowProvider(
            configuration: .production,
            sessionStore: store,
            transport: transport
        )
        _ = try await provider.restoreSession()

        do {
            _ = try await provider.hot(page: PageRequest(number: 1, size: 20))
            Issue.record("Expected the request to fail with an expired session.")
        } catch let error as ProviderError {
            #expect(error == .sessionExpired)
        }

        let clearedSession = try await store.load()
        #expect(clearedSession == nil)
    }

    @Test("person details and works use the observed people endpoints")
    func personDetailsAndWorks() async throws {
        let session = ProviderSession(
            token: "synthetic-token",
            expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
        )
        let transport = StubTransport([
            .json("""
            {
              "ok": true,
              "data": {
                "id": "person-synthetic",
                "name": "Synthetic Performer",
                "favorite": false,
                "tmdb_id": 42,
                "imdb_id": null
              }
            }
            """),
            .json("""
            {
              "ok": true,
              "data": {
                "page": 1,
                "page_size": 60,
                "total": 1,
                "items": [{
                  "id": "movie-synthetic",
                  "type": "movie",
                  "title": "Synthetic Feature"
                }]
              }
            }
            """)
        ])
        let provider = UHDNowProvider(
            sessionStore: MemorySessionStore(session: session),
            transport: transport
        )
        _ = try await provider.restoreSession()

        let person = try await provider.person(id: "person-synthetic")
        let works = try await provider.works(
            forPersonID: person.id,
            page: PageRequest(number: 1, size: 60),
            sort: MediaSort(field: .rating, order: .ascending)
        )

        #expect(person.name == "Synthetic Performer")
        #expect(person.tmdbID == "42")
        #expect(works.items.first?.title == "Synthetic Feature")
        let requests = await transport.requests
        #expect(requests[0].url?.path == "/api/v1/stream/library/persons/person-synthetic")
        #expect(requests[1].url?.path == "/api/v1/stream/library/persons/person-synthetic/works")
        #expect(requests[1].url?.query?.contains("sort_by=rating") == true)
        #expect(requests[1].url?.query?.contains("sort_order=asc") == true)
    }

    @Test("favorite lists map media and people without sharing response types")
    func favoriteLists() async throws {
        let session = ProviderSession(
            token: "synthetic-token",
            expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
        )
        let transport = StubTransport([
            .json("""
            {
              "ok": true,
              "data": {
                "page": 1,
                "page_size": 60,
                "total": 1,
                "items": [{
                  "id": "series-synthetic",
                  "type": "tv",
                  "title": "Synthetic Series",
                  "user_state": { "favorite": true }
                }]
              }
            }
            """),
            .json("""
            {
              "ok": true,
              "data": {
                "page": 1,
                "page_size": 60,
                "total": 1,
                "items": [{
                  "id": "person-synthetic",
                  "name": "Synthetic Performer",
                  "avatar_path": "/img/person-synthetic",
                  "favorite": true
                }]
              }
            }
            """)
        ])
        let provider = UHDNowProvider(
            sessionStore: MemorySessionStore(session: session),
            transport: transport
        )
        _ = try await provider.restoreSession()

        let series = try await provider.favoriteMedia(
            kind: .series,
            page: PageRequest(number: 1, size: 60)
        )
        let people = try await provider.favoritePeople(
            page: PageRequest(number: 1, size: 60)
        )

        #expect(series.items.first?.kind == .series)
        #expect(series.items.first?.userState.favorite == true)
        #expect(people.items.first?.isFavorite == true)
        let requests = await transport.requests
        #expect(requests[0].url?.query?.contains("type=tv") == true)
        #expect(requests[1].url?.query?.contains("type=person") == true)
    }

    @Test("favorite mutations only remove resource kinds with observed delete paths")
    func favoriteMutations() async throws {
        let session = ProviderSession(
            token: "synthetic-token",
            expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
        )
        let transport = StubTransport([
            .json("""
            {
              "ok": true,
              "data": {
                "favorite": true,
                "item_id": "series-synthetic",
                "item_type": "tv"
              }
            }
            """),
            .json("""
            {
              "ok": true,
              "data": {
                "favorite": false,
                "item_id": "series-synthetic",
                "item_type": "tv"
              }
            }
            """)
        ])
        let provider = UHDNowProvider(
            sessionStore: MemorySessionStore(session: session),
            transport: transport
        )
        _ = try await provider.restoreSession()
        let target = FavoriteTarget(id: "series-synthetic", kind: .series)

        #expect(try await provider.setFavorite(true, target: target) == true)
        #expect(try await provider.setFavorite(false, target: target) == false)
        do {
            _ = try await provider.setFavorite(
                false,
                target: FavoriteTarget(id: "movie-synthetic", kind: .movie)
            )
            Issue.record("Expected unobserved movie removal to stay unsupported.")
        } catch let error as ProviderError {
            #expect(error == .unsupported)
        }

        let requests = await transport.requests
        #expect(requests[0].httpMethod == "POST")
        let body = try #require(requests[0].httpBody)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        #expect(object["item_id"] == "series-synthetic")
        #expect(object["item_type"] == "tv")
        #expect(requests[1].httpMethod == "DELETE")
        #expect(requests[1].url?.path == "/api/v1/stream/me/favorites/tv/series-synthetic")
        #expect(requests.count == 2)
    }

    @Test("series playback state maps resume and next-up episode shapes")
    func seriesPlaybackState() async throws {
        let session = ProviderSession(
            token: "synthetic-token",
            expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
        )
        let transport = StubTransport([
            .json("""
            {
              "ok": true,
              "data": {
                "resume": {
                  "item_type": "episode",
                  "item_id": "episode-1",
                  "media_id": "series-1",
                  "title": "Synthetic Episode One",
                  "subtitle": "S1 E1",
                  "season_id": "season-1",
                  "season_number": 1,
                  "episode_number": 1,
                  "duration": 2400,
                  "user_state": {
                    "played": false,
                    "position_ticks": 12000000000,
                    "progress_pct": 50
                  }
                },
                "next_up": {
                  "id": "episode-2",
                  "media_id": "series-1",
                  "season_id": "season-1",
                  "season_number": 1,
                  "episode_number": 2,
                  "title": "Synthetic Episode Two",
                  "duration": 2500,
                  "user_state": {
                    "played": false,
                    "position_ticks": 0,
                    "progress_pct": 0
                  }
                }
              }
            }
            """)
        ])
        let provider = UHDNowProvider(
            sessionStore: MemorySessionStore(session: session),
            transport: transport
        )
        _ = try await provider.restoreSession()

        let state = try await provider.playbackState(seriesID: "series-1")

        #expect(state.resume?.item.id == "episode-1")
        #expect(state.resume?.userState.positionSeconds == 1200)
        #expect(state.resume?.userState.progress == 0.5)
        #expect(state.resume?.seasonNumber == 1)
        #expect(state.nextUp?.item.id == "episode-2")
        #expect(state.nextUp?.episodeNumber == 2)
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/api/v1/stream/tv/series-1/playback-state")
    }

    @Test("seconds and UHDNow ticks round trip")
    func ticksRoundTrip() {
        let ticks = UHDNowTime.ticks(fromSeconds: 123.5)
        #expect(ticks == 1_235_000_000)
        #expect(UHDNowTime.seconds(fromTicks: ticks) == 123.5)
    }
}

private actor StubTransport: HTTPTransport {
    private var responses: [HTTPResult]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [HTTPResult]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        guard !responses.isEmpty else {
            throw StubError.missingResponse
        }
        return responses.removeFirst()
    }
}

private actor MemorySessionStore: ProviderSessionStore {
    private var session: ProviderSession?

    init(session: ProviderSession? = nil) {
        self.session = session
    }

    func load() async throws -> ProviderSession? {
        session
    }

    func save(_ session: ProviderSession) async throws {
        self.session = session
    }

    func clear() async throws {
        session = nil
    }
}

private enum StubError: Error {
    case missingResponse
}

private extension HTTPResult {
    static func json(_ value: String, statusCode: Int = 200) -> HTTPResult {
        HTTPResult(data: Data(value.utf8), statusCode: statusCode)
    }
}
