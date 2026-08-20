import SwiftUI
import CineLarkDomain

struct MediaDetailView: View {
    @State private var model: MediaDetailModel
    @State private var playbackOptions: PlaybackOptionsContext? = nil

    init(
        item: MediaSummary,
        provider: any MediaLibraryProvider,
        playback: PlaybackCoordinator
    ) {
        _model = State(
            initialValue: MediaDetailModel(
                item: item,
                provider: provider,
                playback: playback
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                hero

                if model.item.kind == .movie {
                    movieVersions
                } else {
                    seriesContent
                }

                if let detail = model.detail, !credits(in: detail).isEmpty {
                    cast(credits(in: detail))
                }
            }
            .padding(.bottom, 48)
        }
        .background(Color.black.opacity(0.94))
        .navigationTitle(model.item.title)
        .task {
            await model.load()
        }
        .alert(
            "CineLark",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(item: $playbackOptions) { context in
            PlaybackOptionsView(context: context, playback: model.playback)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(url: model.item.backdropURL)
                .frame(maxWidth: .infinity)
                .frame(height: 430)
                .clipped()
                .overlay {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.32)
                        .allowsHitTesting(false)
                }
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.92)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }

            HStack(alignment: .bottom, spacing: 28) {
                ArtworkView(url: model.item.posterURL)
                    .frame(width: 210, height: 315)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 18, y: 8)

                VStack(alignment: .leading, spacing: 14) {
                    Text(model.item.title)
                        .font(.system(size: 42, weight: .bold, design: .rounded))

                    HStack(spacing: 14) {
                        if let year = model.item.releaseYear {
                            Text(String(year))
                        }
                        if let rating = model.item.rating {
                            Label(
                                rating.formatted(.number.precision(.fractionLength(1))),
                                systemImage: "star.fill"
                            )
                        }
                        if let duration = model.item.durationSeconds {
                            Text(duration.cineLarkDuration)
                        }
                        if let seasons = model.item.totalSeasons {
                            Text("\(seasons) season\(seasons == 1 ? "" : "s")")
                        }
                    }
                    .foregroundStyle(.secondary)

                    if !model.item.genres.isEmpty {
                        Text(model.item.genres.map(\.name).joined(separator: " · "))
                            .font(.callout.weight(.medium))
                    }

                    if let synopsis = model.item.synopsis, !synopsis.isEmpty {
                        Text(synopsis)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .frame(maxWidth: 720, alignment: .leading)
                    }

                    Button {
                        Task { await model.toggleFavorite() }
                    } label: {
                        if model.isUpdatingFavorite {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(
                                model.isFavorite ? "Favorited" : "Add to Favorites",
                                systemImage: model.isFavorite ? "heart.fill" : "heart"
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(model.isFavorite ? .orange : .accentColor)
                    .disabled(
                        model.isUpdatingFavorite ||
                        (model.isFavorite && !model.canRemoveFavorite)
                    )
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 40)
        }
    }

    @ViewBuilder
    private var movieVersions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Versions")
                .font(.title2.bold())

            if model.isLoading && model.movieAssets.isEmpty {
                ProgressView("Loading versions…")
            } else if model.movieAssets.isEmpty {
                Text("No playable version is currently available.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.movieAssets) { asset in
                    AssetRow(asset: asset) {
                        presentMovieOptions(preferredAssetID: asset.id)
                    }
                }
            }
        }
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private var seriesContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Episodes")
                    .font(.title2.bold())
                Spacer()
                if !model.seasons.isEmpty {
                    Picker("Season", selection: seasonSelection) {
                        ForEach(model.seasons) { season in
                            Text(season.title).tag(season.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }

            if model.isLoadingEpisodes {
                ProgressView("Loading episodes…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(model.episodes) { episode in
                        EpisodeRow(episode: episode) {
                            presentEpisodeOptions(episode)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 40)
    }

    private var seasonSelection: Binding<String> {
        Binding(
            get: { model.selectedSeasonID ?? model.seasons.first?.id ?? "" },
            set: { seasonID in
                Task { await model.selectSeason(seasonID) }
            }
        )
    }

    private func presentMovieOptions(preferredAssetID: String?) {
        playbackOptions = PlaybackOptionsContext(
            item: PlayableItem(id: model.item.id, kind: .movie),
            title: model.item.title,
            artworkURL: model.item.backdropURL ?? model.item.posterURL,
            startPositionSeconds: model.item.userState.positionSeconds,
            initialAssets: model.movieAssets,
            preferredAssetID: preferredAssetID
        )
    }

    private func presentEpisodeOptions(_ episode: Episode) {
        let seasonTitle = model.seasons.first {
            $0.id == episode.seasonID
        }?.title
        playbackOptions = PlaybackOptionsContext(
            item: PlayableItem(id: episode.id, kind: .episode),
            title: episode.title,
            subtitle: [seasonTitle, "Episode \(episode.number)"]
                .compactMap { $0 }
                .joined(separator: " · "),
            artworkURL: episode.thumbnailURL ?? model.item.backdropURL,
            startPositionSeconds: episode.userState.positionSeconds
        )
    }

    private func cast(_ people: [PersonCredit]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cast & Crew")
                .font(.title2.bold())

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(Array(people.prefix(36))) { person in
                        NavigationLink(value: person) {
                            VStack(spacing: 9) {
                                ArtworkView(
                                    url: person.avatarURL,
                                    placeholderSystemImage: "person.fill"
                                )
                                .frame(width: 104, height: 104)
                                .clipShape(Circle())
                                Text(person.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                if let character = person.character, !character.isEmpty {
                                    Text(character)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 130)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 40)
    }

    private func credits(in detail: MediaDetail) -> [PersonCredit] {
        var seen: Set<String> = []
        return (detail.directors + detail.cast).filter { seen.insert($0.id).inserted }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let action: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            ArtworkView(url: episode.thumbnailURL)
                .frame(width: 220, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if episode.versionCount > 0 {
                        Text("\(episode.versionCount) version\(episode.versionCount == 1 ? "" : "s")")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 7) {
                Text("Episode \(episode.number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                Text(episode.title)
                    .font(.headline)
                if let synopsis = episode.synopsis {
                    Text(synopsis)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if episode.userState.progress > 0 && !episode.userState.played {
                    ProgressView(value: episode.userState.progress)
                        .progressViewStyle(.linear)
                        .tint(.cyan)
                        .frame(maxWidth: 280)
                }
            }

            Spacer()

            Button(action: action) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
