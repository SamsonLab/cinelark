import Foundation
import CineLarkDomain
import CineLarkPlayback

@MainActor
final class PlaybackCoordinator {
    private let provider: any MediaLibraryProvider
    private let launcher: any PlaybackLaunching

    init(provider: any MediaLibraryProvider, launcher: any PlaybackLaunching) {
        self.provider = provider
        self.launcher = launcher
    }

    func assets(for item: PlayableItem) async throws -> [MediaAsset] {
        try await provider.assets(for: item)
    }

    func playFirst(
        item: PlayableItem,
        title: String,
        startPositionSeconds: Double = 0
    ) async throws {
        guard let asset = try await assets(for: item).first else {
            throw ProviderError.notFound
        }
        try await play(
            asset: asset,
            title: title,
            startPositionSeconds: startPositionSeconds
        )
    }

    func play(
        asset: MediaAsset,
        title: String,
        startPositionSeconds: Double = 0
    ) async throws {
        let url = try await provider.playbackURL(for: asset)
        let descriptor = PlaybackDescriptor(
            url: url,
            title: title,
            startPositionSeconds: startPositionSeconds
        )
        try await launcher.open(descriptor)
    }
}
