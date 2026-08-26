import ComposableArchitecture
import Foundation
import CineLarkDomain
import CineLarkPlayback
import CineLarkPluginAPI

struct PlaybackEngineClient: Sendable {
    var events: @Sendable () -> AsyncStream<CineLarkPlayback.PlaybackEvent>
    var open: @Sendable (
        UUID,
        SourcePlaybackDescriptor,
        String,
        Double
    ) async throws -> Void
    var send: @Sendable (PlaybackControlCommand, UUID) async throws -> Void
}

extension PlaybackEngineClient: DependencyKey {
    static let liveValue = Self(
        events: { AsyncStream { $0.finish() } },
        open: { _, _, _, _ in throw PlaybackLaunchError.bridgeUnavailable },
        send: { _, _ in throw PlaybackLaunchError.bridgeUnavailable }
    )

    static let testValue = liveValue
}

extension DependencyValues {
    var playbackEngine: PlaybackEngineClient {
        get { self[PlaybackEngineClient.self] }
        set { self[PlaybackEngineClient.self] = newValue }
    }
}

extension PlaybackEngineClient {
    @MainActor
    static func live(launcher: any PlaybackLaunching) -> Self {
        let events = launcher.events
        return Self(
            events: { events },
            open: { id, source, title, startPosition in
                try await launcher.open(
                    PlaybackDescriptor(
                        id: id,
                        url: source.url,
                        title: title,
                        startPositionSeconds: startPosition,
                        headers: source.headers
                    )
                )
            },
            send: { command, sessionID in
                try await launcher.send(command, sessionID: sessionID)
            }
        )
    }
}
