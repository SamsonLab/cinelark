import ComposableArchitecture
import Foundation
import Testing
import CineLarkDomain
import CineLarkPluginAPI

@testable import CineLark

@MainActor
struct SearchFeatureTests {
    @Test("Debounced search is latest-wins")
    func latestWins() async {
        let clock = TestClock()
        let sourceID = SourceID(rawValue: UUID())
        let resultID = CatalogItemID(rawValue: UUID())
        let page = MediaPage(
            items: [
                LocatedMediaItem(
                    catalogID: resultID,
                    locator: MediaLocatorID(
                        sourceID: sourceID,
                        providerItemID: "latest"
                    ),
                    summary: MediaSummary(
                        id: "latest",
                        kind: .movie,
                        title: "Latest"
                    )
                )
            ],
            nextCursor: nil,
            total: 1
        )
        let queries = LockIsolated<[String]>([])
        let store = TestStore(
            initialState: SearchFeature.State(sourceID: sourceID)
        ) {
            SearchFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable },
                search: { term, _ in
                    queries.withValue { $0.append(term) }
                    return page
                }
            )
        }

        await store.send(.view(.queryChanged("first"))) {
            $0.query = "first"
            $0.isSearching = true
        }
        await store.send(.view(.queryChanged("latest"))) {
            $0.query = "latest"
        }

        await clock.advance(by: .milliseconds(350))
        await store.receive(
            .internal(.response(
                term: "latest",
                query: MediaQuery(scope: SourceScope(sourceID: sourceID), limit: 60),
                appending: false,
                .success(page)
            ))
        ) {
            $0.resultIDs = [resultID]
            $0.results = [
                resultID: MediaSummary(id: "latest", kind: .movie, title: "Latest")
            ]
            $0.total = 1
            $0.isSearching = false
        }

        #expect(queries.value == ["latest"])
    }
}
