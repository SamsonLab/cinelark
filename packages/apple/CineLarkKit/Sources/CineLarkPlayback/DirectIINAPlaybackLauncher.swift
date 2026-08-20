import AppKit
import CineLarkDomain

@MainActor
public final class DirectIINAPlaybackLauncher: PlaybackLaunching {
    private let workspace: NSWorkspace

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func open(_ descriptor: PlaybackDescriptor) async throws {
        guard let applicationURL = workspace.urlForApplication(
            withBundleIdentifier: "com.colliderli.iina"
        ) else {
            throw PlaybackLaunchError.iinaNotInstalled
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false

        try await withCheckedThrowingContinuation { continuation in
            workspace.open(
                [descriptor.url],
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
                if error == nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PlaybackLaunchError.launchFailed)
                }
            }
        }
    }
}
