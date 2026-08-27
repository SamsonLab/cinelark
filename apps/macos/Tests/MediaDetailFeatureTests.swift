import ComposableArchitecture
import Foundation
import Testing
import CineLarkDomain
import CineLarkPluginAPI
import CineLarkProfile

@testable import CineLark

@MainActor
struct MediaDetailFeatureTests {
    @Test("Hierarchy episode playback preserves episode identity and series metadata")
    func episodePlaybackIdentity() async {
        let sourceID = SourceID(rawValue: UUID())
        let seriesLocator = MediaLocatorID(
            sourceID: sourceID,
            providerItemID: "series-1"
        )
        let genre = Genre(id: 1, name: "Drama", slug: "drama")
        let item = MediaSummary(
            id: seriesLocator.providerItemID,
            kind: .series,
            title: "Synthetic Series",
            genres: [genre]
        )
        let episode = Episode(
            id: "episode-1",
            seriesID: seriesLocator.providerItemID,
            seasonID: "season-1",
            number: 1,
            title: "Synthetic Pilot",
            synopsis: nil,
            airDate: nil,
            thumbnailURL: nil,
            durationSeconds: 1_800,
            versionCount: 1,
            hasMultipleVersions: false,
            userState: .empty
        )
        let store = TestStore(
            initialState: MediaDetailFeature.State(
                locator: seriesLocator,
                profileID: nil,
                initialItem: item
            )
        ) {
            MediaDetailFeature()
        }

        await store.send(.view(.episodeSelected(episode)))
        await store.receive(.delegate(.play(
            locator: MediaLocatorID(sourceID: sourceID, providerItemID: episode.id),
            title: episode.title,
            kind: .episode,
            artworkURL: nil,
            metadata: ProfileMediaMetadataSnapshot(
                genres: [ProfileGenreSnapshot(
                    name: genre.name,
                    slug: genre.slug
                )]
            ),
            startPositionSeconds: 0
        )))
    }
}
