import SwiftUI
import Sparkle
import CineLarkDomain
import CineLarkGateway
import CineLarkPersistence
import CineLarkPlayback
import CineLarkUHDNow

@main
@MainActor
struct CineLarkApp: App {
    @NSApplicationDelegateAdaptor(CineLarkAppDelegate.self) private var appDelegate
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.systemDefault.rawValue
    @State private var model: AppModel
    @State private var shortcuts: ShortcutCoordinator
    @State private var remoteTextInput: RemoteTextInputCoordinator
    @State private var remote: RemoteCoordinator
    private let gateway: CineLarkNativeGateway
    private let updateMonitor: SparkleUpdateMonitor
    private let updaterController: SPUStandardUpdaterController

    init() {
        let updateMonitor = SparkleUpdateMonitor()
        let gateway = CineLarkNativeGateway()
        self.gateway = gateway
        self.updateMonitor = updateMonitor
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updateMonitor,
            userDriverDelegate: nil
        )
        let sessionStore = KeychainSessionStore()
        let upstreamProvider = UHDNowProvider(sessionStore: sessionStore)
        let metadataCache = PersistentMetadataCache(
            configuration: MetadataCacheConfiguration(schemaVersion: 4)
        )
        let provider = CachedMediaLibraryProvider(
            upstream: upstreamProvider,
            cache: metadataCache,
            namespace: "uhdnow-v1"
        )
        let launcher = ManagedIINAPlaybackLauncher(transport: gateway.iina)
        let model = AppModel(provider: provider, launcher: launcher)
        let shortcuts = ShortcutCoordinator()
        let remoteTextInput = RemoteTextInputCoordinator()
        _model = State(initialValue: model)
        _shortcuts = State(initialValue: shortcuts)
        _remoteTextInput = State(initialValue: remoteTextInput)
        _remote = State(
            initialValue: RemoteCoordinator(
                model: model,
                shortcuts: shortcuts,
                textInput: remoteTextInput,
                client: gateway.remote
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                model: model,
                updater: updaterController.updater,
                updateMonitor: updateMonitor,
                remote: remote
            )
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
                .environment(shortcuts)
                .environment(remoteTextInput)
                .frame(minWidth: 960, minHeight: 640)
                .task {
                    shortcuts.start()
                    appDelegate.prepareForTermination = { [weak model, weak shortcuts, weak remote, gateway] in
                        await model?.prepareForTermination()
                        await remote?.stop()
                        await gateway.shutdown()
                        shortcuts?.stop()
                    }
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
                        return
                    }
                    await remote.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                SparkleMenuUpdateButton(updater: updaterController.updater)
            }
        }
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: storedLanguage) ?? .systemDefault
    }
}
