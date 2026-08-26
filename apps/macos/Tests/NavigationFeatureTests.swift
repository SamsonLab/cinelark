import ComposableArchitecture
import Testing
import CineLarkDomain

@testable import CineLark

@MainActor
struct NavigationFeatureTests {
    @Test("Detail navigation does not change the global sidebar preference")
    func sidebarIsStableAcrossDetailNavigation() async {
        let store = TestStore(initialState: NavigationFeature.State()) {
            NavigationFeature()
        }
        let item = MediaSummary(id: "movie-1", kind: .movie, title: "Movie")

        await store.send(.view(.sidebarVisibilityChanged(false))) {
            $0.$sidebarVisible.withLock { $0 = false }
        }
        await store.send(.view(.mediaRequested(item, transitionID: nil))) {
            $0.path.append(
                .media(MediaRouteFeature.State(item: item, transitionID: nil))
            )
        }
        await store.send(.view(.backRequested)) {
            $0.path.removeLast()
        }

        #expect(store.state.sidebarVisible == false)
    }

    @Test("Selecting a sidebar section clears detail navigation")
    func selectingSectionClearsPath() async {
        let item = MediaSummary(id: "movie-1", kind: .movie, title: "Movie")
        var state = NavigationFeature.State()
        state.path.append(.media(MediaRouteFeature.State(item: item, transitionID: nil)))
        let store = TestStore(initialState: state) {
            NavigationFeature()
        }

        await store.send(.view(.sectionSelected(.movies))) {
            $0.selection = .movies
            $0.path.removeAll()
        }
    }
}
