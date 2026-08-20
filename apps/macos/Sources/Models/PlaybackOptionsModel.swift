import AppKit
import Foundation
import Observation
import CineLarkDomain

struct PlaybackOptionsContext: Identifiable, Sendable {
    let id = UUID()
    let item: PlayableItem
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let startPositionSeconds: Double
    let initialAssets: [MediaAsset]
    let preferredAssetID: String?

    init(
        item: PlayableItem,
        title: String,
        subtitle: String? = nil,
        artworkURL: URL? = nil,
        startPositionSeconds: Double = 0,
        initialAssets: [MediaAsset] = [],
        preferredAssetID: String? = nil
    ) {
        self.item = item
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.startPositionSeconds = max(startPositionSeconds, 0)
        self.initialAssets = initialAssets
        self.preferredAssetID = preferredAssetID
    }
}

@Observable
@MainActor
final class PlaybackOptionsModel {
    let context: PlaybackOptionsContext
    private(set) var assets: [MediaAsset]
    private(set) var selectedAssetID: String?
    private(set) var expandedAssetID: String?
    private(set) var isLoading = false
    private(set) var isPlaying = false
    private(set) var resolvingLinkAssetID: String?
    private(set) var copiedLinkAssetID: String?
    var errorMessage: String?

    @ObservationIgnored private let playback: PlaybackCoordinator

    init(context: PlaybackOptionsContext, playback: PlaybackCoordinator) {
        self.context = context
        self.playback = playback
        self.assets = context.initialAssets
        self.selectedAssetID = context.initialAssets.first {
            $0.id == context.preferredAssetID
        }?.id ?? context.initialAssets.first?.id
    }

    var selectedAsset: MediaAsset? {
        assets.first { $0.id == selectedAssetID }
    }

    func load() async {
        guard assets.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedAssets = try await playback.assets(for: context.item)
            guard !Task.isCancelled else { return }
            assets = loadedAssets
            selectedAssetID = loadedAssets.first?.id
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func select(_ asset: MediaAsset) {
        selectedAssetID = asset.id
    }

    func toggleDetails(for asset: MediaAsset) {
        expandedAssetID = expandedAssetID == asset.id ? nil : asset.id
    }

    func playSelected() async -> Bool {
        guard let selectedAsset, !isPlaying else { return false }
        isPlaying = true
        defer { isPlaying = false }
        do {
            try await playback.play(
                item: context.item,
                asset: selectedAsset,
                title: context.title,
                startPositionSeconds: context.startPositionSeconds
            )
            return true
        } catch {
            present(error)
            return false
        }
    }

    func copyPlaybackLink(for asset: MediaAsset) async {
        await performLinkAction(for: asset) {
            let url = try await self.playback.playbackURL(for: asset)
            try self.copyToPasteboard(url, assetID: asset.id)
        }
    }

    func copyDownloadLink(for asset: MediaAsset) async {
        await performLinkAction(for: asset) {
            let url = try await self.playback.downloadURL(for: asset)
            try self.copyToPasteboard(url, assetID: asset.id)
        }
    }

    func openDownload(for asset: MediaAsset) async {
        await performLinkAction(for: asset) {
            let url = try await self.playback.downloadURL(for: asset)
            guard NSWorkspace.shared.open(url) else {
                throw PlaybackOptionsError.openDownloadFailed
            }
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func performLinkAction(
        for asset: MediaAsset,
        action: () async throws -> Void
    ) async {
        guard resolvingLinkAssetID == nil else { return }
        resolvingLinkAssetID = asset.id
        defer { resolvingLinkAssetID = nil }
        do {
            try await action()
        } catch {
            present(error)
        }
    }

    private func copyToPasteboard(_ url: URL, assetID: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(url.absoluteString, forType: .string) else {
            throw PlaybackOptionsError.copyFailed
        }
        copiedLinkAssetID = assetID
        scheduleCopiedStateReset(for: assetID)
    }

    private func scheduleCopiedStateReset(for assetID: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard self?.copiedLinkAssetID == assetID else { return }
            self?.copiedLinkAssetID = nil
        }
    }

    private func present(_ error: Error) {
        if let error = error as? LocalizedError,
           let description = error.errorDescription {
            errorMessage = description
        } else {
            errorMessage = "CineLark could not prepare this version."
        }
    }
}

private enum PlaybackOptionsError: Error, LocalizedError {
    case copyFailed
    case openDownloadFailed

    var errorDescription: String? {
        switch self {
        case .copyFailed:
            "CineLark could not copy the link."
        case .openDownloadFailed:
            "CineLark could not open the download link."
        }
    }
}
