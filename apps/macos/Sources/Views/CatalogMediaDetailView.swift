import SwiftUI
import ComposableArchitecture
import CineLarkDomain

struct CatalogMediaDetailView: View {
    @Bindable var store: StoreOf<MediaDetailFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 28) {
                    MediaArtworkSurface(
                        item: store.item,
                        url: store.item.posterURL ?? store.item.backdropURL,
                        locator: store.locator,
                        size: CGSize(width: 240, height: 360),
                        role: .playback,
                        transitionID: nil
                    )

                    VStack(alignment: .leading, spacing: 16) {
                        Text(store.item.title)
                            .font(.system(size: 38, weight: .bold))

                        if let originalTitle {
                            Text(originalTitle)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        MediaFacts(item: store.item, fields: .extended)

                        if !store.item.genres.isEmpty {
                            Text(store.item.genres.map(\.name).joined(separator: " · "))
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        if let synopsis = store.item.synopsis, !synopsis.isEmpty {
                            Text(synopsis)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(8)
                        }

                        HStack {
                            Button {
                                store.send(.view(.playPrimary))
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                store.send(.view(.toggleFavorite))
                            } label: {
                                Label(
                                    store.isFavorite ? "Favorited" : "Favorite",
                                    systemImage: store.isFavorite ? "heart.fill" : "heart"
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(store.isUpdatingFavorite)
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                }

                if !store.seasons.isEmpty {
                    Picker("Season", selection: seasonBinding) {
                        ForEach(store.seasons) { season in
                            Text(season.title).tag(Optional(season.id))
                        }
                    }
                    .pickerStyle(.segmented)

                    if store.isLoadingEpisodes {
                        ProgressView()
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(store.episodes) { episode in
                                Button {
                                    store.send(.view(.episodeSelected(episode)))
                                } label: {
                                    HStack {
                                        Text("\(episode.number)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 32)
                                        VStack(alignment: .leading) {
                                            Text(episode.title)
                                            if let synopsis = episode.synopsis {
                                                Text(synopsis)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "play.circle")
                                    }
                                    .padding(12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let detail = store.detail,
                   !detail.directors.isEmpty || !detail.cast.isEmpty {
                    peopleSection("Directors", people: detail.directors)
                    peopleSection("Cast", people: detail.cast)
                }

                if let failure = store.failure {
                    Text(String(describing: failure))
                        .foregroundStyle(.red)
                }
            }
            .padding(40)
        }
        .background(CineLarkPageBackground())
        .navigationTitle(store.item.title)
        .task { store.send(.view(.appeared)) }
    }

    private var seasonBinding: Binding<String?> {
        Binding(
            get: { store.selectedSeasonID },
            set: { if let value = $0 { store.send(.view(.seasonSelected(value))) } }
        )
    }

    private var originalTitle: String? {
        guard let originalTitle = store.item.originalTitle,
              !originalTitle.isEmpty,
              originalTitle.caseInsensitiveCompare(store.item.title) != .orderedSame
        else { return nil }
        return originalTitle
    }

    private func peopleSection(_ title: String, people: [PersonCredit]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(people) { person in
                        NavigationLink(
                            state: NavigationFeature.Path.State.person(
                                PersonRouteFeature.State(
                                    person: person,
                                    sourceID: store.locator.sourceID
                                )
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name)
                                    .font(.headline)
                                if let character = person.character, !character.isEmpty {
                                    Text(character)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 180, alignment: .leading)
                            .padding(14)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
