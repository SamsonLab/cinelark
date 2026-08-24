import Foundation
import Testing
import CineLarkDomain
@testable import CineLarkPlayback

@Suite("Playback bridge protocol")
struct BridgeProtocolTests {
    @Test("Swift envelope MAC matches the JavaScript and Rust vector")
    func sharedAuthenticationVector() throws {
        let secret = Data(repeating: 7, count: 32)
        let date = try #require(
            ISO8601DateFormatter().date(from: "2026-08-20T03:09:00Z")
        )
        let envelope = BridgeEnvelope(
            id: UUID(uuidString: "4ff6c27e-1415-473f-8764-451d6a3369cb")!,
            type: "player.requestState",
            sessionID: UUID(uuidString: "6f55936d-5950-44fd-a696-f989d41785cc")!,
            sequence: 42,
            payload: [
                "z": .array([.integer(2), .integer(1)]),
                "a": .bool(true)
            ],
            secret: secret,
            date: date
        )

        #expect(envelope.mac == "MJSUf0t2XseeHfgYLbOFp7x5kIYnV5OT_oBWOhfQovc")
        #expect(envelope.isAuthenticated(with: secret))
        #expect(!envelope.isAuthenticated(with: Data(repeating: 8, count: 32)))
    }

    @Test("Play commands with URLs match the broker canonicalization")
    func playCommandAuthentication() throws {
        let date = try #require(
            ISO8601DateFormatter().date(from: "2026-08-20T03:09:00Z")
        )
        let sessionID = UUID(uuidString: "6f55936d-5950-44fd-a696-f989d41785cc")!
        let envelope = BridgeEnvelope(
            id: UUID(uuidString: "d845187a-802b-4216-af45-b3f8d3981a43")!,
            type: "player.play",
            sessionID: sessionID,
            sequence: 1,
            payload: [
                "playbackID": .string(sessionID.uuidString.lowercased()),
                "url": .string("https://media.example/video?token=<redacted>"),
                "title": .string("Synthetic Feature"),
                "startPositionSeconds": .number(12.5),
                "presentation": .object(["fullscreen": .bool(false)])
            ],
            secret: Data(0..<32),
            date: date
        )
        #expect(envelope.mac == "f-U2R3wA0BH372_NRygSR_sK3PLkSf6CsmDgNLGRoKU")
    }

    @Test("IINA termination finalizes the active playback once")
    func iinaTerminationFinalizesActivePlayback() {
        let playbackID = UUID()
        var tracker = IINAApplicationTerminationTracker()
        tracker.begin(playbackID: playbackID)

        #expect(tracker.applicationDidTerminate(bundleIdentifier: "com.example.other") == nil)
        #expect(
            tracker.applicationDidTerminate(bundleIdentifier: "com.colliderli.iina")
                == playbackID
        )
        #expect(tracker.applicationDidTerminate(bundleIdentifier: "com.colliderli.iina") == nil)
    }

    @Test("terminal plugin events suppress duplicate IINA termination")
    func terminalPluginEventsSuppressTermination() {
        let playbackID = UUID()
        var tracker = IINAApplicationTerminationTracker()
        tracker.begin(playbackID: playbackID)
        tracker.finish(playbackID: playbackID)

        #expect(tracker.applicationDidTerminate(bundleIdentifier: "com.colliderli.iina") == nil)
    }

    @Test("Playback descriptors start managed players in fullscreen")
    func playbackStartsInFullscreen() {
        let descriptor = PlaybackDescriptor(
            url: URL(string: "https://media.example/video?token=<redacted>")!,
            title: "Synthetic Feature"
        )

        #expect(descriptor.startsInFullscreen)
    }

    @Test("Queued player events retain the active item playback ID")
    func queuedEventsRouteToActiveItem() {
        let sessionID = UUID()
        let firstPlaybackID = sessionID
        let secondPlaybackID = UUID()
        var router = IINAPlaybackEventRouter()

        #expect(
            router.playbackID(
                eventType: "player.fileLoaded",
                sessionID: sessionID,
                payloadPlaybackID: firstPlaybackID
            ) == firstPlaybackID
        )
        #expect(
            router.playbackID(
                eventType: "player.positionChanged",
                sessionID: sessionID,
                payloadPlaybackID: nil
            ) == firstPlaybackID
        )
        #expect(
            router.playbackID(
                eventType: "player.fileLoaded",
                sessionID: sessionID,
                payloadPlaybackID: secondPlaybackID
            ) == secondPlaybackID
        )
        #expect(
            router.playbackID(
                eventType: "player.ended",
                sessionID: sessionID,
                payloadPlaybackID: secondPlaybackID
            ) == secondPlaybackID
        )
    }

    @Test("Canonical JSON sorts nested object keys")
    func canonicalJSON() {
        let value = JSONValue.object([
            "z": .object(["b": .integer(2), "a": .integer(1)]),
            "a": .bool(true)
        ])
        #expect(value.canonicalJSON == #"{"a":true,"z":{"a":1,"b":2}}"#)
    }

    @Test("Pairing keys use unpadded base64url")
    func pairingKeyEncoding() throws {
        let secret = Data(0..<32)
        let encoded = secret.base64URLEncodedString()
        #expect(!encoded.contains("="))
        #expect(Data(base64URLEncoded: encoded) == secret)
    }
}
