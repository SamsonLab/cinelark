import SwiftUI
import CineLarkDomain
import CineLarkPersistence
import CineLarkPlayback
import CineLarkUHDNow

@main
@MainActor
struct CineLarkApp: App {
    @State private var model: AppModel

    init() {
        let sessionStore = KeychainSessionStore()
        let upstreamProvider = UHDNowProvider(sessionStore: sessionStore)
        let metadataCache = PersistentMetadataCache(
            configuration: MetadataCacheConfiguration(schemaVersion: 2)
        )
        let provider = CachedMediaLibraryProvider(
            upstream: upstreamProvider,
            cache: metadataCache,
            namespace: "uhdnow-v1"
        )
        let launcher = DirectIINAPlaybackLauncher()
        _model = State(
            initialValue: AppModel(provider: provider, launcher: launcher)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }
}
