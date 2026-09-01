import SwiftUI
import Sparkle
import ComposableArchitecture
import CineLarkDomain
import CineLarkCatalog
import CineLarkEmby
import CineLarkGateway
import CineLarkInsights
import CineLarkPersistence
import CineLarkPlayback
import CineLarkPluginAPI
import CineLarkProfile

@main
@MainActor
struct CineLarkApp: App {
    @NSApplicationDelegateAdaptor(CineLarkAppDelegate.self) private var appDelegate
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.systemDefault.rawValue
    @State private var shortcuts: ShortcutCoordinator
    @State private var remoteTextInput: RemoteTextInputCoordinator
    @State private var remote: RemoteCoordinator
    private let store: StoreOf<AppFeature>
    private let gateway: CineLarkNativeGateway
    private let artworkResolver: ArtworkResolutionClient
    private let cloudKitAuditOperation: (@Sendable () async -> Void)?
    private let updateMonitor: SparkleUpdateMonitor
    private let updaterController: SPUStandardUpdaterController

    init() {
        let environment = ProcessInfo.processInfo.environment
        let isRunningTests = environment["XCTestConfigurationFilePath"] != nil
        let cloudKitAuditRequest = CloudKitAuditLaunchRequest(environment: environment)
        let updateMonitor = SparkleUpdateMonitor()
        let gateway = CineLarkNativeGateway()
        self.gateway = gateway
        self.updateMonitor = updateMonitor
        updaterController = SPUStandardUpdaterController(
            startingUpdater: cloudKitAuditRequest == nil,
            updaterDelegate: updateMonitor,
            userDriverDelegate: nil
        )
        let launcher = ManagedIINAPlaybackLauncher(transport: gateway.iina)
        let shortcuts = ShortcutCoordinator()
        let remoteTextInput = RemoteTextInputCoordinator()
        _shortcuts = State(initialValue: shortcuts)
        _remoteTextInput = State(initialValue: remoteTextInput)
        let remote = RemoteCoordinator(
            shortcuts: shortcuts,
            textInput: remoteTextInput,
            client: gateway.remote
        )
        _remote = State(initialValue: remote)
        let sourceSecrets = KeychainSecretStore(
            service: "com.samsonlab.cinelark.source-token"
        )
        let legacySourceSecrets = KeychainSecretStore(
            service: "com.samsonlab.cinelark.provider"
        )
        try? LegacyProviderArtifacts().removeMetadataCache()
        let clientIDKey = "cinelark.client.id"
        let legacyDeviceIDKey = "cinelark.device.id"
        let storedClientID = UserDefaults.standard.string(forKey: clientIDKey)
            ?? UserDefaults.standard.string(forKey: legacyDeviceIDKey)
        let clientID: ClientID
        if let storedClientID, let value = UUID(uuidString: storedClientID) {
            clientID = ClientID(rawValue: value)
        } else {
            clientID = ClientID(rawValue: UUID())
        }
        UserDefaults.standard.set(clientID.description, forKey: clientIDKey)
        let embyFactory = EmbyPluginFactory(
            device: EmbyDeviceIdentity(id: clientID.description, appVersion: "0.1.11"),
            tokenVault: EmbyTokenVault(
                load: { sourceID in
                    try await sourceSecrets.load(account: sourceID.rawValue.uuidString)
                },
                save: { token, sourceID in
                    try await sourceSecrets.save(token, account: sourceID.rawValue.uuidString)
                },
                remove: { sourceID in
                    try await sourceSecrets.remove(account: sourceID.rawValue.uuidString)
                }
            )
        )
        let registry: PluginRegistry
        do {
            registry = try PluginRegistry(factories: [embyFactory])
        } catch {
            preconditionFailure("Invalid built-in plugin registry: \(error)")
        }
        let mediaPlatform = MediaSourcePlatform(registry: registry)
        artworkResolver = .live(platform: mediaPlatform)
        let catalogURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("CineLark", isDirectory: true)
            .appendingPathComponent("Catalog.sqlite")
        try? FileManager.default.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let catalog: CoreDataCatalogStore
        do {
            catalog = try CoreDataCatalogStore(storeURL: catalogURL)
        } catch {
            preconditionFailure("Unable to open the local media catalog: \(error)")
        }
        let profileRepository: CoreDataProfileRepository
        do {
            profileRepository = try CoreDataProfileRepository(
                configuration: .init(
                    cloudStoreURL: isRunningTests
                        ? nil
                        : catalogURL
                            .deletingLastPathComponent()
                            .appendingPathComponent("ProfileCloud.sqlite"),
                    localStoreURL: isRunningTests
                        ? nil
                        : catalogURL
                            .deletingLastPathComponent()
                            .appendingPathComponent("ProfileLocal.sqlite"),
                    cloudKitContainerIdentifier: isRunningTests
                        ? nil
                        : "iCloud.com.samsonlab.cinelark",
                    inMemory: isRunningTests
                )
            )
        } catch {
            preconditionFailure("Unable to open the profile repository: \(error)")
        }
        if let cloudKitAuditRequest {
            cloudKitAuditOperation = {
                do {
                    try await CloudKitAuditCapture.run(
                        repository: profileRepository,
                        request: cloudKitAuditRequest
                    )
                } catch {
                    let message = Data("CloudKit audit capture failed.\n".utf8)
                    try? FileHandle.standardError.write(contentsOf: message)
                }
            }
        } else {
            cloudKitAuditOperation = nil
        }
        let appStore = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.mediaPlatform = .live(
                platform: mediaPlatform,
                catalog: catalog,
                cleanupLegacyCredentials: { pluginID, sourceID in
                    guard pluginID == EmbyPluginFactory.legacyUHDNowPluginID else { return }
                    try? await legacySourceSecrets.remove(
                        account: "uhdnow-\(sourceID.rawValue.uuidString)"
                    )
                }
            )
            $0.profiles = .live(repository: profileRepository, clientID: clientID)
            $0.insights = .live(
                service: ViewingInsightsService(
                    repository: profileRepository,
                    catalog: catalog,
                    clientID: clientID
                )
            )
            $0.playbackEngine = .live(launcher: launcher)
            $0.remote = .live(coordinator: remote)
            $0.cache = .live(
                catalog: catalog,
                artworkUsage: {
                    UInt64(try await CineLarkImagePipeline.cache.diskStorageSize)
                },
                clearArtwork: {
                    await CineLarkImagePipeline.cache.clearCache()
                }
            )
        }
        store = appStore
        remote.configurePlayback { command in
            if command == .stop {
                appStore.send(.playback(.view(.stop)))
            } else {
                appStore.send(.playback(.view(.control(command))))
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                updater: updaterController.updater,
                updateMonitor: updateMonitor,
                remote: remote,
                store: store
            )
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
                .environment(shortcuts)
                .environment(remoteTextInput)
                .environment(\.artworkResolutionClient, artworkResolver)
                .frame(minWidth: 960, minHeight: 640)
                .task {
                    if let cloudKitAuditOperation {
                        await cloudKitAuditOperation()
                        NSApplication.shared.terminate(nil)
                        return
                    }
                    store.send(.view(.appeared))
                    shortcuts.start()
                    appDelegate.prepareForTermination = { [weak shortcuts, weak remote, gateway] in
                        await remote?.stop()
                        await gateway.shutdown()
                        shortcuts?.stop()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                SparkleMenuUpdateButton(updater: updaterController.updater)
            }
        }

        Settings {
            CineLarkSettingsView(
                updater: updaterController.updater,
                remote: remote,
                store: store
            )
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
                .environment(\.artworkResolutionClient, artworkResolver)
        }
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: storedLanguage) ?? .systemDefault
    }
}
