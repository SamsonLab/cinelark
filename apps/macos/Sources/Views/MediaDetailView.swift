import SwiftUI
import CineLarkDomain

struct MediaDetailView: View {
    @Environment(\.appLanguage) private var language
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

                if let synopsis = model.item.synopsis, !synopsis.isEmpty {
                    overview(synopsis)
                }

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
            Button(language.localized("general.dismiss"), role: .cancel) { model.dismissError() }
        } message: {
            Text(language.userFacingError(model.errorMessage))
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

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 28) {
                    ArtworkView(url: model.item.posterURL)
                        .frame(width: 210, height: 315)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.10))
                                .allowsHitTesting(false)
                        }
                        .shadow(radius: 18, y: 8)

                    heroMetadata(titleSize: 42)
                        .frame(minWidth: 360, maxWidth: .infinity, alignment: .leading)
                }

                heroMetadata(titleSize: 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
        }
    }

    private func heroMetadata(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.item.title)
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .lineLimit(2)
                .help(model.item.title)

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
                    Text(language.duration(duration))
                }
                if let seasons = model.item.totalSeasons {
                    Text(
                        language.localized(
                            seasons == 1
                                ? "detail.season_count_one"
                                : "detail.season_count_many",
                            String(seasons)
                        )
                    )
                }
            }
            .monospacedDigit()
            .foregroundStyle(.secondary)

            if !model.item.genres.isEmpty {
                Text(model.item.genres.map(\.name).joined(separator: " · "))
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
            }

            if let synopsis = model.item.synopsis, !synopsis.isEmpty {
                Text(synopsis)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: 720, alignment: .leading)
            }

            Button {
                Task { await model.toggleFavorite() }
            } label: {
                if model.isUpdatingFavorite {
                    ProgressView().controlSize(.small)
                } else {
                    Label(
                        language.localized(
                            model.isFavorite
                                ? "detail.favorite"
                                : "detail.add_favorite"
                        ),
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private func overview(_ synopsis: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.localized("detail.overview"))
                .font(.title2.bold())
            Text(synopsis)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: 760, alignment: .leading)
        }
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private var movieVersions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.localized("detail.versions"))
                .font(.title2.bold())

            if model.isLoading && model.movieAssets.isEmpty {
                ProgressView(language.localized("detail.loading_versions"))
            } else if model.movieAssets.isEmpty {
                Text(language.localized("detail.no_versions"))
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
                Text(language.localized("detail.episodes"))
                    .font(.title2.bold())
                Spacer()
                if !model.seasons.isEmpty {
                    Picker(language.localized("detail.season"), selection: seasonSelection) {
                        ForEach(model.seasons) { season in
                            Text(season.title).tag(season.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }

            if model.isLoadingEpisodes {
                ProgressView(language.localized("detail.loading_episodes"))
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
            subtitle: [
                seasonTitle,
                language.localized("episode.number", String(episode.number))
            ]
                .compactMap { $0 }
                .joined(separator: " · "),
            artworkURL: episode.thumbnailURL ?? model.item.backdropURL,
            startPositionSeconds: episode.userState.positionSeconds
        )
    }

    private func cast(_ people: [PersonCredit]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(language.localized("detail.cast_crew"))
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
                                    .help(person.name)
                                if let character = person.character, !character.isEmpty {
                                    Text(character)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 130)
                        }
                        .buttonStyle(CineLarkPressButtonStyle())
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    let episode: Episode
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ArtworkView(url: episode.thumbnailURL)
                    .frame(width: 220, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.10))
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .topTrailing) {
                        if episode.versionCount > 0 {
                            Text(
                                language.localized(
                                    episode.versionCount == 1
                                        ? "episode.version_one"
                                        : "episode.version_many",
                                    String(episode.versionCount)
                                )
                            )
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                        }
                    }

                VStack(alignment: .leading, spacing: 7) {
                    Text(language.localized("episode.number", String(episode.number)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(episode.title)
                        .font(.headline)
                    if let synopsis = episode.synopsis {
                        Text(synopsis)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .help(synopsis)
                    }
                    if episode.userState.progress > 0 && !episode.userState.played {
                        ProgressView(value: episode.userState.progress)
                            .progressViewStyle(.linear)
                            .tint(Color.accentColor)
                            .frame(maxWidth: 280)
                    }
                }

                Spacer(minLength: 16)

                Image(systemName: "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 40)
                    .background(
                        isHovering ? Color.accentColor : Color.accentColor.opacity(0.82),
                        in: Capsule()
                    )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CineLarkPressButtonStyle())
        .background(
            isHovering ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isHovering
                        ? Color.accentColor.opacity(0.65)
                        : Color.white.opacity(0.10),
                    lineWidth: isHovering ? 1.5 : 1
                )
        }
        .scaleEffect(isHovering && !reduceMotion ? 1.004 : 1)
        .offset(y: isHovering && !reduceMotion ? -1 : 0)
        .shadow(color: .black.opacity(isHovering ? 0.30 : 0), radius: 12, y: 6)
        .onHover { isHovering = $0 }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isHovering
        )
        .accessibilityLabel(
            language.localized(
                "episode.accessibility_label",
                language.localized("episode.number", String(episode.number)),
                episode.title
            )
        )
        .accessibilityHint(language.localized("episode.choose_hint"))
    }
}
