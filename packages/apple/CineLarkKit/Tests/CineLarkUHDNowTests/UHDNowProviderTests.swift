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
                  "rating": 8,
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
                playPath: "/play/video/asset-synthetic"
            )
        )

        #expect(url.scheme == "https")
        #expect(url.host == "media.example")
        #expect(url.path == "/play/video/asset-synthetic")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems == [URLQueryItem(name: "token", value: "synthetic-token")])
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
