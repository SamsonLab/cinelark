import ComposableArchitecture
import Foundation
import Testing
import CineLarkDomain
import CineLarkPluginAPI

@testable import CineLark

@MainActor
struct PersonDetailFeatureTests {
    @Test("Person detail and credits load through one cancellable response")
    func loadsDetailAndCredits() async {
        let sourceID = SourceID(rawValue: UUID())
        let person = PersonCredit(
            id: "person-1",
            name: "Director",
            character: nil,
            avatarURL: nil,
            order: 0
        )
        let detail = PersonDetail(
            id: person.id,
            name: person.name,
            isFavorite: false
        )
        let catalogID = CatalogItemID(rawValue: UUID())
        let work = MediaSummary(id: "movie-1", kind: .movie, title: "Movie")
        let page = MediaPage(
            items: [
                LocatedMediaItem(
                    catalogID: catalogID,
                    locator: MediaLocatorID(
                        sourceID: sourceID,
                        providerItemID: work.id
                    ),
                    summary: work
                )
            ],
            nextCursor: nil,
            total: 1
        )
        let queries = LockIsolated<[MediaQuery]>([])
        let store = TestStore(
            initialState: PersonDetailFeature.State(
                sourceID: sourceID,
                initialPerson: person
            )
        ) {
            PersonDetailFeature()
        } withDependencies: {
            $0.mediaPlatform = MediaPlatformClient(
                descriptors: { [] },
                cachedPage: { _ in throw MediaSourceFailure.unavailable },
                refreshPage: { _ in throw MediaSourceFailure.unavailable },
                person: { requestedSourceID, requestedPersonID in
                    #expect(requestedSourceID == sourceID)
                    #expect(requestedPersonID == person.id)
                    return detail
                },
                works: { requestedPersonID, query in
                    #expect(requestedPersonID == person.id)
                    queries.withValue { $0.append(query) }
                    return page
                }
            )
        }

        await store.send(.view(.appeared)) {
            $0.isLoading = true
        }
        await store.receive(.internal(.response(.success(
            PersonDetailFeature.Response(detail: detail, works: [work])
        )))) {
            $0.detail = detail
            $0.works = [work]
            $0.isLoading = false
        }

        #expect(queries.value == [
            MediaQuery(
                scope: SourceScope(sourceID: sourceID),
                kinds: [.movie, .series],
                filters: [.provider(name: "cinelark.person", value: person.id)],
                limit: 120
            )
        ])
    }
}
