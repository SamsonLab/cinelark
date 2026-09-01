import ComposableArchitecture
import Foundation
import CineLarkPluginAPI
import CineLarkProfile

@Reducer
struct AppFeature {
    enum BootstrapState: Equatable {
        case idle
        case loading
        case ready
    }

    @ObservableState
    struct State: Equatable {
        var bootstrap: BootstrapState = .idle
        var bootstrapPerformanceInterval: CineLarkPerformanceInterval?
        var pendingSelection: ActiveProfileSelection?
        var pendingBootstrapSelection: ActiveProfileSelection?
        var navigation = NavigationFeature.State()
        var profile = ProfileFeature.State()
        var source = SourceFeature.State()
        var library = LibraryFeature.State()
        var search = SearchFeature.State()
        var insights = InsightsFeature.State()
        var playback = PlaybackFeature.State()
        var remote = RemoteFeature.State()
        var cache = CacheFeature.State()

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.bootstrap == rhs.bootstrap
                && lhs.pendingSelection == rhs.pendingSelection
                && lhs.pendingBootstrapSelection == rhs.pendingBootstrapSelection
                && lhs.navigation == rhs.navigation
                && lhs.profile == rhs.profile
                && lhs.source == rhs.source
                && lhs.library == rhs.library
                && lhs.search == rhs.search
                && lhs.insights == rhs.insights
                && lhs.playback == rhs.playback
                && lhs.remote == rhs.remote
                && lhs.cache == rhs.cache
        }
    }

    enum Action {
        case view(View)
        case `internal`(Internal)
        case navigation(NavigationFeature.Action)
        case profile(ProfileFeature.Action)
        case source(SourceFeature.Action)
        case library(LibraryFeature.Action)
        case search(SearchFeature.Action)
        case insights(InsightsFeature.Action)
        case playback(PlaybackFeature.Action)
        case remote(RemoteFeature.Action)
        case cache(CacheFeature.Action)

        enum View {
            case appeared
            case confirmSelectionChange
            case cancelSelectionChange
        }

        enum Internal {
            case sourceBindingSaved(ActiveProfileSelection)
            case sourceBindingFailed(ProfileClientFailure)
        }
    }

    @Dependency(\.profiles) private var profiles
    @Dependency(\.performance) private var performance

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appeared):
                guard state.bootstrap == .idle else { return .none }
                state.bootstrap = .loading
                state.bootstrapPerformanceInterval = performance.start(.appBootstrap)
                return .merge(
                    .send(.source(.view(.loadAvailablePlugins))),
                    .send(.profile(.view(.appeared))),
                    .send(.playback(.view(.appeared))),
                    .send(.remote(.view(.appAppeared)))
                )

            case .view(.confirmSelectionChange):
                guard state.pendingSelection != nil else { return .none }
                return .send(.playback(.view(.stop)))

            case .view(.cancelSelectionChange):
                state.pendingSelection = nil
                return .none

            case let .internal(.sourceBindingSaved(selection)):
                if state.playback.active != nil {
                    state.pendingSelection = selection
                    return .none
                }
                return .send(.profile(.internal(.commitSelection(selection))))

            case let .internal(.sourceBindingFailed(failure)):
                state.profile.failure = failure
                return .none

            case let .profile(.internal(.loaded(.success(bootstrap)))):
                state.pendingBootstrapSelection = bootstrap.selection
                return .send(.source(.internal(.restoreSources(bootstrap.sources))))

            case .profile(.internal(.loaded(.failure))):
                if let interval = state.bootstrapPerformanceInterval {
                    performance.finish(interval, .failure)
                    state.bootstrapPerformanceInterval = nil
                }
                return .none

            case let .source(.internal(.sourcesRestored(installedSourceIDs, _, failure))):
                guard let selection = state.pendingBootstrapSelection else { return .none }
                state.pendingBootstrapSelection = nil
                state.bootstrap = .ready
                if let interval = state.bootstrapPerformanceInterval {
                    performance.finish(interval, failure == nil ? .success : .failure)
                    state.bootstrapPerformanceInterval = nil
                }
                if let sourceID = selection.sourceID, !installedSourceIDs.contains(sourceID) {
                    return .send(.profile(.internal(.commitSelection(
                        ActiveProfileSelection(
                            profileID: selection.profileID,
                            sourceID: nil
                        )
                    ))))
                }
                return applyContext(selection)

            case let .profile(.delegate(.sourceSelectionRequested(sourceID))):
                let selection = ActiveProfileSelection(
                    profileID: state.profile.activeProfileID,
                    sourceID: sourceID
                )
                if state.playback.active != nil {
                    state.pendingSelection = selection
                    return .none
                }
                return .send(.profile(.internal(.commitSelection(selection))))

            case let .profile(.delegate(.selectionChanged(selection))):
                state.pendingBootstrapSelection = nil
                return applyContext(selection)

            case let .profile(.internal(.repositoryChanged(.userState(profileID)))):
                guard state.profile.activeProfileID == profileID else { return .none }
                var effects: [Effect<Action>] = [
                    .send(.library(.view(.loadOverview)))
                ]
                if state.navigation.selection == .insights {
                    effects.append(.send(.insights(.view(.reload))))
                }
                return .merge(effects)

            case let .profile(.internal(.repositoryChanged(.mediaMetadata(profileID)))):
                guard
                    state.profile.activeProfileID == profileID,
                    state.navigation.selection == .insights,
                    !state.insights.isLoading
                else { return .none }
                return .send(.insights(.view(.reload)))

            case .profile(.internal(.repositoryChanged(.external))):
                var effects: [Effect<Action>] = [
                    .send(.library(.view(.loadOverview)))
                ]
                if state.navigation.selection == .insights {
                    effects.append(.send(.insights(.view(.reload))))
                }
                return .merge(effects)

            case let .navigation(.delegate(.play(
                locator,
                title,
                kind,
                artworkURL,
                metadata,
                startPosition,
                variantID
            ))):
                return .send(.playback(.view(.play(
                    locator: locator,
                    title: title,
                    kind: kind,
                    artworkURL: artworkURL,
                    metadata: metadata,
                    startPositionSeconds: startPosition,
                    variantID: variantID
                ))))

            case let .library(.delegate(.play(
                locator,
                title,
                kind,
                artworkURL,
                startPosition
            ))):
                return .send(.playback(.view(.play(
                    locator: locator,
                    title: title,
                    kind: kind,
                    artworkURL: artworkURL,
                    metadata: nil,
                    startPositionSeconds: startPosition,
                    variantID: nil
                ))))

            case let .source(.delegate(.sourceSaved(source))):
                let selection = ActiveProfileSelection(
                    profileID: state.profile.activeProfileID,
                    sourceID: source.id
                )
                guard let profileID = selection.profileID else {
                    return .send(.profile(.internal(.commitSelection(selection))))
                }
                let existingBinding = state.profile.bindings.first {
                    $0.profileID == profileID && $0.sourceID == source.id
                }
                let binding = ProfileSourceBinding(
                    profileID: profileID,
                    sourceID: source.id,
                    remoteUserID: source.configuration.remoteUserID,
                    mirrorsRemoteState: existingBinding?.mirrorsRemoteState ?? false
                )
                return .run { send in
                    do {
                        try await profiles.saveBinding(binding)
                        await send(.internal(.sourceBindingSaved(selection)))
                    } catch {
                        let failure = (error as? ProfileClientFailure)
                            ?? .unavailable(String(describing: error))
                        await send(.internal(.sourceBindingFailed(failure)))
                    }
                }

            case .playback(.delegate(.stopped)):
                guard let selection = state.pendingSelection else { return .none }
                state.pendingSelection = nil
                return .send(.profile(.internal(.commitSelection(selection))))

            case .cache(.delegate(.willClear)):
                return .merge(
                    .send(.library(.view(.cacheWillClear))),
                    .send(.search(.view(.cacheWillClear))),
                    .send(.navigation(.view(.cacheWillClear)))
                )

            case .cache(.delegate(.didClear)):
                return .none

            case .navigation, .profile, .source, .library, .search, .insights,
                 .playback, .remote, .cache:
                return .none
            }
        }
        Scope(state: \.navigation, action: \.navigation) {
            NavigationFeature()
        }
        Scope(state: \.profile, action: \.profile) {
            ProfileFeature()
        }
        Scope(state: \.source, action: \.source) {
            SourceFeature()
        }
        Scope(state: \.library, action: \.library) {
            LibraryFeature()
        }
        Scope(state: \.search, action: \.search) {
            SearchFeature()
        }
        Scope(state: \.insights, action: \.insights) {
            InsightsFeature()
        }
        Scope(state: \.playback, action: \.playback) {
            PlaybackFeature()
        }
        Scope(state: \.remote, action: \.remote) {
            RemoteFeature()
        }
        Scope(state: \.cache, action: \.cache) {
            CacheFeature()
        }
    }

    private func applyContext(_ selection: ActiveProfileSelection) -> Effect<Action> {
        .merge(
            .send(.library(.view(.contextChanged(
                profileID: selection.profileID,
                sourceID: selection.sourceID
            )))),
            .send(.search(.view(.sourceChanged(selection.sourceID)))),
            .send(.insights(.view(.contextChanged(
                profileID: selection.profileID,
                sourceID: selection.sourceID
            )))),
            .send(.playback(.view(.contextChanged(selection.profileID)))),
            .send(.navigation(.view(.contextChanged(
                profileID: selection.profileID,
                sourceID: selection.sourceID
            ))))
        )
    }
}
