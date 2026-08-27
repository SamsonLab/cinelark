import ComposableArchitecture
import Foundation
import CineLarkDomain
import CineLarkPluginAPI
import CineLarkProfile

enum LibrarySelection: Hashable, Sendable {
    case home
    case movies
    case series
    case favorites
    case search
    case insights
}

@Reducer
struct MediaRouteFeature {
    @ObservableState
    struct State: Equatable {
        let item: MediaSummary
        let transitionID: UUID?
        let sourceID: SourceID?
        let profileID: ProfileID?
        var detail: MediaDetailFeature.State?

        init(
            item: MediaSummary,
            transitionID: UUID?,
            sourceID: SourceID? = nil,
            profileID: ProfileID? = nil
        ) {
            self.item = item
            self.transitionID = transitionID
            self.sourceID = sourceID
            self.profileID = profileID
            self.detail = sourceID.map {
                MediaDetailFeature.State(
                    locator: MediaLocatorID(sourceID: $0, providerItemID: item.id),
                    profileID: profileID,
                    initialItem: item
                )
            }
        }
    }

    enum Action: Equatable {
        case detail(MediaDetailFeature.Action)
    }

    var body: some ReducerOf<Self> {
        EmptyReducer()
            .ifLet(\.detail, action: \.detail) {
                MediaDetailFeature()
            }
    }
}

@Reducer
struct CollectionRouteFeature {
    @ObservableState
    struct State: Equatable {
        let collection: MediaCollection
    }

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}

@Reducer
struct PersonRouteFeature {
    @ObservableState
    struct State: Equatable {
        let person: PersonCredit
        let sourceID: SourceID?
        var detail: PersonDetailFeature.State?

        init(person: PersonCredit, sourceID: SourceID?) {
            self.person = person
            self.sourceID = sourceID
            self.detail = sourceID.map {
                PersonDetailFeature.State(sourceID: $0, initialPerson: person)
            }
        }
    }

    enum Action: Equatable {
        case detail(PersonDetailFeature.Action)
    }

    var body: some ReducerOf<Self> {
        EmptyReducer()
            .ifLet(\.detail, action: \.detail) {
                PersonDetailFeature()
            }
    }
}

@Reducer
struct NavigationFeature {
    @Reducer
    enum Path {
        case media(MediaRouteFeature)
        case collection(CollectionRouteFeature)
        case person(PersonRouteFeature)
    }

    @ObservableState
    struct State: Equatable {
        @Shared(.sidebarVisible) var sidebarVisible = true
        var selection: LibrarySelection = .home
        var activeSourceID: SourceID?
        var activeProfileID: ProfileID?
        var path = StackState<Path.State>()
    }

    enum Action {
        case view(View)
        case path(StackActionOf<Path>)
        case delegate(Delegate)

        enum View {
            case backRequested
            case cacheWillClear
            case contextChanged(profileID: ProfileID?, sourceID: SourceID?)
            case collectionRequested(MediaCollection)
            case mediaRequested(MediaSummary, transitionID: UUID?)
            case personRequested(PersonCredit)
            case sectionSelected(LibrarySelection)
            case sidebarVisibilityChanged(Bool)
        }

        enum Delegate {
            case play(
                locator: MediaLocatorID,
                title: String,
                kind: MediaKind,
                artworkURL: URL?,
                metadata: ProfileMediaMetadataSnapshot?,
                startPositionSeconds: Double
            )
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .path(.element(id: _, action: .media(.detail(.delegate(.play(
                locator,
                title,
                kind,
                artworkURL,
                metadata,
                startPositionSeconds
            )))))):
                return .send(.delegate(.play(
                    locator: locator,
                    title: title,
                    kind: kind,
                    artworkURL: artworkURL,
                    metadata: metadata,
                    startPositionSeconds: startPositionSeconds
                )))

            case .path, .delegate:
                return .none

            case .view(.backRequested):
                guard !state.path.isEmpty else { return .none }
                state.path.removeLast()
                return .none

            case .view(.cacheWillClear):
                state.path.removeAll()
                return .none

            case let .view(.collectionRequested(collection)):
                state.path.append(
                    .collection(CollectionRouteFeature.State(collection: collection))
                )
                return .none

            case let .view(.mediaRequested(item, transitionID)):
                state.path.append(
                    .media(
                        MediaRouteFeature.State(
                            item: item,
                            transitionID: transitionID,
                            sourceID: state.activeSourceID,
                            profileID: state.activeProfileID
                        )
                    )
                )
                return .none

            case let .view(.contextChanged(profileID, sourceID)):
                state.activeProfileID = profileID
                state.activeSourceID = sourceID
                state.path.removeAll()
                return .none

            case let .view(.personRequested(person)):
                state.path.append(.person(PersonRouteFeature.State(
                    person: person,
                    sourceID: state.activeSourceID
                )))
                return .none

            case let .view(.sectionSelected(selection)):
                state.selection = selection
                state.path.removeAll()
                return .none

            case let .view(.sidebarVisibilityChanged(isVisible)):
                state.$sidebarVisible.withLock { $0 = isVisible }
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

extension NavigationFeature.Path.State: Equatable {}

extension SharedKey where Self == AppStorageKey<Bool> {
    fileprivate static var sidebarVisible: Self {
        appStorage("cinelarkSidebarVisible")
    }
}
