import ComposableArchitecture
import Foundation
import CineLarkProfile
import CineLarkPluginAPI

@Reducer
struct SourceFeature {
    struct SetupState: Equatable {
        let pluginID: PluginID
        var discovered: [DiscoveredSource] = []
        var baseURL = ""
        var displayName = ""
        var validatedConfiguration: SourceConfiguration?
        var isDiscovering = false
        var isValidating = false
        var isAuthenticating = false
        var failure: MediaSourceFailure?
    }

    @ObservableState
    struct State: Equatable {
        var availablePlugins: [CineLarkPluginDescriptor] = []
        var persistedSources: [PersistedMediaSource] = []
        var installedSourceIDs: Set<SourceID> = []
        var setup: SetupState?
        var isLoading = false
        var failure: MediaSourceFailure?
    }

    enum Action: Equatable {
        case view(View)
        case `internal`(Internal)
        case delegate(Delegate)

        enum View: Equatable {
            case loadAvailablePlugins
            case beginSetup(PluginID)
            case discover
            case chooseDiscovered(DiscoveredSource)
            case updateBaseURL(String)
            case updateDisplayName(String)
            case validate
            case authenticate(username: String, password: String)
            case cancelSetup
        }

        enum Internal: Equatable {
            case pluginsLoaded([CineLarkPluginDescriptor])
            case restoreSources([PersistedMediaSource])
            case sourcesRestored(Set<SourceID>, MediaSourceFailure?)
            case discoveryCompleted(Result<[DiscoveredSource], MediaSourceFailure>)
            case validationCompleted(Result<SourceConfiguration, MediaSourceFailure>)
            case authenticationCompleted(Result<PersistedMediaSource, MediaSourceFailure>)
        }

        enum Delegate: Equatable {
            case sourceSaved(PersistedMediaSource)
        }
    }

    private enum CancelID {
        case restore
        case discovery
        case validation
        case authentication
    }

    @Dependency(\.mediaPlatform) private var mediaPlatform
    @Dependency(\.profiles) private var profiles
    @Dependency(\.uuid) private var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.loadAvailablePlugins):
                state.isLoading = true
                return .run { send in
                    await send(.internal(.pluginsLoaded(mediaPlatform.descriptors())))
                }

            case let .internal(.pluginsLoaded(plugins)):
                state.isLoading = false
                state.availablePlugins = plugins
                return .none

            case let .internal(.restoreSources(sources)):
                state.persistedSources = sources
                state.isLoading = true
                return .run { send in
                    var installed = Set<SourceID>()
                    var firstFailure: MediaSourceFailure?
                    for source in sources {
                        do {
                            try await mediaPlatform.install(source.pluginID, source.configuration)
                            installed.insert(source.id)
                        } catch is CancellationError {
                            return
                        } catch {
                            firstFailure = firstFailure ?? Self.normalize(error)
                        }
                    }
                    await send(.internal(.sourcesRestored(installed, firstFailure)))
                }
                .cancellable(id: CancelID.restore, cancelInFlight: true)

            case let .internal(.sourcesRestored(ids, failure)):
                state.isLoading = false
                state.installedSourceIDs = ids
                state.failure = failure
                return .none

            case let .view(.beginSetup(pluginID)):
                state.setup = SetupState(pluginID: pluginID)
                return .none

            case .view(.discover):
                guard var setup = state.setup else { return .none }
                setup.isDiscovering = true
                setup.failure = nil
                state.setup = setup
                return .run { [pluginID = setup.pluginID] send in
                    do {
                        await send(.internal(.discoveryCompleted(.success(
                            try await mediaPlatform.discover(pluginID)
                        ))))
                    } catch {
                        await send(.internal(.discoveryCompleted(.failure(Self.normalize(error)))))
                    }
                }
                .cancellable(id: CancelID.discovery, cancelInFlight: true)

            case let .view(.chooseDiscovered(source)):
                state.setup?.baseURL = source.address.absoluteString
                state.setup?.displayName = source.name
                return .none

            case let .view(.updateBaseURL(value)):
                state.setup?.baseURL = value
                state.setup?.validatedConfiguration = nil
                return .none

            case let .view(.updateDisplayName(value)):
                state.setup?.displayName = value
                return .none

            case .view(.validate):
                guard var setup = state.setup else { return .none }
                let trimmed = setup.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = Self.normalizedURL(trimmed) else {
                    setup.failure = .invalidResponse
                    state.setup = setup
                    return .none
                }
                setup.isValidating = true
                setup.failure = nil
                state.setup = setup
                let sourceID = SourceID(rawValue: uuid())
                let displayName = setup.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                return .run { [pluginID = setup.pluginID] send in
                    do {
                        let identity = try await mediaPlatform.validate(pluginID, url)
                        await send(.internal(.validationCompleted(.success(
                            SourceConfiguration(
                                sourceID: sourceID,
                                baseURL: url,
                                serverIdentity: identity,
                                displayName: displayName.isEmpty
                                    ? url.host ?? "Media Source"
                                    : displayName
                            )
                        ))))
                    } catch {
                        await send(.internal(.validationCompleted(.failure(Self.normalize(error)))))
                    }
                }
                .cancellable(id: CancelID.validation, cancelInFlight: true)

            case let .view(.authenticate(username, password)):
                guard
                    var setup = state.setup,
                    let configuration = setup.validatedConfiguration
                else { return .none }
                setup.isAuthenticating = true
                setup.failure = nil
                state.setup = setup
                let credentials = SourceCredentials(username: username, password: password)
                return .run { [pluginID = setup.pluginID] send in
                    do {
                        let authenticated = try await mediaPlatform.authenticate(
                            pluginID,
                            configuration,
                            credentials
                        )
                        try await profiles.saveSource(pluginID, authenticated)
                        await send(.internal(.authenticationCompleted(.success(
                            PersistedMediaSource(
                                pluginID: pluginID,
                                configuration: authenticated
                            )
                        ))))
                    } catch {
                        await send(.internal(.authenticationCompleted(.failure(Self.normalize(error)))))
                    }
                }
                .cancellable(id: CancelID.authentication, cancelInFlight: true)

            case .view(.cancelSetup):
                state.setup = nil
                return .merge(
                    .cancel(id: CancelID.discovery),
                    .cancel(id: CancelID.validation),
                    .cancel(id: CancelID.authentication)
                )

            case let .internal(.discoveryCompleted(.success(sources))):
                state.setup?.isDiscovering = false
                state.setup?.discovered = sources
                return .none

            case let .internal(.discoveryCompleted(.failure(failure))):
                state.setup?.isDiscovering = false
                state.setup?.failure = failure
                return .none

            case let .internal(.validationCompleted(.success(configuration))):
                state.setup?.isValidating = false
                state.setup?.validatedConfiguration = configuration
                return .none

            case let .internal(.validationCompleted(.failure(failure))):
                state.setup?.isValidating = false
                state.setup?.failure = failure
                return .none

            case let .internal(.authenticationCompleted(.success(source))):
                state.setup = nil
                state.persistedSources.removeAll { $0.id == source.id }
                state.persistedSources.append(source)
                state.installedSourceIDs.insert(source.id)
                return .send(.delegate(.sourceSaved(source)))

            case let .internal(.authenticationCompleted(.failure(failure))):
                state.setup?.isAuthenticating = false
                state.setup?.failure = failure
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private static func normalizedURL(_ value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil { return url }
        return URL(string: "http://\(value)")
    }

    private static func normalize(_ error: Error) -> MediaSourceFailure {
        if let failure = error as? MediaSourceFailure { return failure }
        if error is CancellationError { return .unavailable }
        return .transport(String(describing: error))
    }
}
