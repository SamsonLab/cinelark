import SwiftUI
import CineLarkDomain
import CineLarkPersistence
import CineLarkPlayback
import CineLarkUHDNow

@main
@MainActor
struct CineLarkApp: App {
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.systemDefault.rawValue
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
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: storedLanguage) ?? .systemDefault
    }
}
