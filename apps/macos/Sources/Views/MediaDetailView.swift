import SwiftUI
import CineLarkDomain

struct MediaDetailView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.mediaTransitionNamespace) private var transitionNamespace
    @State private var model: MediaDetailModel
    @State private var playbackOptions: PlaybackOptionsContext? = nil
    @State private var showsAllEpisodes = false
    private let transitionID: UUID?

    init(
        item: MediaSummary,
        provider: any MediaLibraryProvider,
        playback: PlaybackCoordinator,
        transitionID: UUID? = nil
    ) {
        self.transitionID = transitionID
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
        .background(CineLarkPageBackground())
        .navigationTitle(model.item.title)
        .task(id: model.playback.playbackStateRevision) {
            if model.detail == nil {
                await model.load()
            } else {
                await model.refreshPlaybackContext()
            }
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
        ZStack(alignment: .top) {
            CineLarkCinematicBackdrop(
                url: model.heroBackdropURL,
                height: 620,
                leadingShade: 0.90
            )

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        language.localized(
                            model.item.kind == .movie ? "detail.movie" : "detail.series"
                        )
                    )
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.accentColor)

                    Text(model.item.title)
                        .font(CineLarkDesign.Typography.heroTitle)
                        .lineLimit(2)
                        .help(model.item.title)

                    if let originalTitle = model.item.originalTitle,
                       originalTitle != model.item.title {
                        Text(originalTitle)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 100)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)

                HStack(alignment: .top, spacing: 36) {
                    ArtworkView(url: model.heroPosterURL)
                        .frame(width: 250, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .mediaMatchedGeometry(
                            id: transitionID,
                            namespace: transitionNamespace,
                            isSource: false
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.12))
                                .allowsHitTesting(false)
                        }
                        .shadow(color: .black.opacity(0.55), radius: 24, y: 12)

                    heroMetadata
                        .frame(minWidth: 420, maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 40)
                .padding(.top, 34)
            }
        }
    }

    private var heroMetadata: some View {
        VStack(alignment: .leading, spacing: 16) {
            MediaFacts(
                item: model.item,
                fields: .extended,
                spacing: 14,
                font: .body
            )

            if !model.item.genres.isEmpty {
                HStack(spacing: 9) {
                    ForEach(model.item.genres.prefix(5)) { genre in
                        Text(genre.name)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .overlay {
                                Capsule().stroke(Color.white.opacity(0.18))
                            }
                    }
                }
            }

            if let synopsis = model.item.synopsis, !synopsis.isEmpty {
                Text(synopsis)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .lineSpacing(4)
                    .frame(maxWidth: 900, alignment: .leading)
            }

            playbackSummary

            HStack(spacing: 12) {
                if model.isLoading && !model.canStartPlayback {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text(language.localized("detail.preparing_playback"))
                            .font(.headline)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .glassEffect(.regular, in: Capsule())
                } else {
                    Button {
                        Task { await model.playPrimary() }
                    } label: {
                        if model.isStartingPlayback {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(primaryPlaybackLabel, systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                    .disabled(!model.canStartPlayback || model.isStartingPlayback)
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
                .buttonStyle(.glass)
                .controlSize(.extraLarge)
                .tint(model.isFavorite ? .orange : .accentColor)
                .disabled(
                    model.isUpdatingFavorite ||
                    (model.isFavorite && !model.canRemoveFavorite)
                )

                playbackStatusBadge
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    @ViewBuilder
    private var playbackSummary: some View {
        if model.item.kind == .series,
           let resume = model.resumableSeriesItem {
            Label(
                language.localized(
                    "detail.last_watched",
                    episodeDescriptor(resume),
                    language.progressPercent(resume.userState.progress)
                ),
                systemImage: "clock.arrow.circlepath"
            )
            .font(.callout.weight(.semibold))
            .foregroundStyle(.yellow)
        }
    }

    @ViewBuilder
    private var playbackStatusBadge: some View {
        if model.item.userState.played {
            Label(language.localized("detail.watched"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .glassEffect(.regular, in: Capsule())
        } else if model.item.userState.progress > 0 || model.resumableSeriesItem != nil {
            Label(language.localized("detail.watching"), systemImage: "eye.fill")
                .foregroundStyle(.yellow)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .glassEffect(.regular, in: Capsule())
        }
    }

    private var primaryPlaybackLabel: String {
        switch model.item.kind {
        case .movie:
            if model.item.userState.played {
                return language.localized("detail.replay")
            }
            if model.item.userState.progress > 0 {
                return language.localized(
                    "detail.continue",
                    language.progressPercent(model.item.userState.progress)
                )
            }
            return language.localized("detail.play")
        case .series:
            if let resume = model.resumableSeriesItem {
                return language.localized(
                    "detail.continue_episode",
                    episodeDescriptor(resume),
                    language.progressPercent(resume.userState.progress)
                )
            }
            if let nextUp = model.seriesPlaybackState?.nextUp {
                return language.localized("detail.play_episode", episodeDescriptor(nextUp))
            }
            if let firstEpisode = model.episodes.first {
                return language.localized(
                    "detail.play_episode",
                    episodeDescriptor(firstEpisode)
                )
            }
            return language.localized("detail.play")
        }
    }

    private func episodeDescriptor(_ item: ContinueWatchingItem) -> String {
        if let seasonNumber = item.seasonNumber,
           let episodeNumber = item.episodeNumber {
            return language.localized(
                "episode.season_episode",
                String(seasonNumber),
                String(episodeNumber)
            )
        }
        if let episode = model.episodes.first(where: { $0.id == item.item.id }) {
            return episodeDescriptor(episode)
        }
        return item.subtitle ?? item.title
    }

    private func episodeDescriptor(_ episode: Episode) -> String {
        let seasonNumber = model.seasons.first { $0.id == episode.seasonID }?.number
        if let seasonNumber {
            return language.localized(
                "episode.season_episode",
                String(seasonNumber),
                String(episode.number)
            )
        }
        return language.localized("episode.number", String(episode.number))
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
                InlineMovieVersionsView(
                    context: PlaybackOptionsContext(
                        item: PlayableItem(id: model.item.id, kind: .movie),
                        title: model.item.title,
                        artworkURL: model.heroBackdropURL ?? model.heroPosterURL,
                        startPositionSeconds: model.item.userState.played
                            ? 0
                            : model.item.userState.positionSeconds,
                        initialAssets: model.movieAssets
                    ),
                    playback: model.playback
                )
            }
        }
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private var seriesContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(language.localized("detail.episodes"))
                    .font(.title2.bold())
                if !model.seasons.isEmpty {
                    Text(
                        language.localized(
                            model.seasons.count == 1
                                ? "detail.season_count_one"
                                : "detail.season_count_many",
                            String(model.seasons.count)
                        )
                    )
                    .foregroundStyle(.secondary)
                }
            }

            if !model.seasons.isEmpty {
                seasonStrip
            }

            if (model.isLoading && model.seasons.isEmpty) || model.isLoadingEpisodes {
                ProgressView(language.localized("detail.loading_episodes"))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(visibleEpisodes) { episode in
                        EpisodeRow(episode: episode) {
                            presentEpisodeOptions(episode)
                        }
                    }
                }

                if model.episodes.count > Self.collapsedEpisodeCount {
                    Button {
                        showsAllEpisodes.toggle()
                    } label: {
                        Label(
                            language.localized(
                                showsAllEpisodes
                                    ? "episode.show_less"
                                    : "episode.show_more",
                                String(model.episodes.count - Self.collapsedEpisodeCount)
                            ),
                            systemImage: showsAllEpisodes ? "chevron.up" : "chevron.down"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
        }
        .padding(.horizontal, 40)
        .onChange(of: model.selectedSeasonID) {
            showsAllEpisodes = false
        }
    }

    private static let collapsedEpisodeCount = 6

    private var visibleEpisodes: [Episode] {
        guard !showsAllEpisodes else { return model.episodes }
        return Array(model.episodes.prefix(Self.collapsedEpisodeCount))
    }

    private var seasonStrip: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(model.seasons) { season in
                    SeasonPill(
                        season: season,
                        isSelected: model.selectedSeasonID == season.id
                    ) {
                        Task { await model.selectSeason(season.id) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
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
            artworkPreviewSize: episode.thumbnailURL == nil
                ? nil
                : CGSize(width: 220, height: 124),
            startPositionSeconds: episode.userState.played
                ? 0
                : episode.userState.positionSeconds,
            seriesID: model.item.id
        )
    }

    private func cast(_ people: [PersonCredit]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(language.localized("detail.cast_crew"))
                .font(.title2.bold())

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(Array(people.prefix(36))) { person in
                        PersonCreditLink(person: person)
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

private struct PersonCreditLink: View {
    let person: PersonCredit
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(value: person) {
            VStack(spacing: 9) {
                ArtworkView(
                    url: person.avatarURL,
                    placeholderSystemImage: "person.fill"
                )
                .frame(width: 104, height: 104)
                .clipShape(Circle())
                .cineLarkFocusSurface(
                    isActive: isHovering || isFocused,
                    cornerRadius: 52,
                    scale: 1.06
                )
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
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }
}

private struct InlineMovieVersionsView: View {
    @Environment(\.appLanguage) private var language
    @State private var model: PlaybackOptionsModel

    init(context: PlaybackOptionsContext, playback: PlaybackCoordinator) {
        _model = State(
            initialValue: PlaybackOptionsModel(
                context: context,
                playback: playback
            )
        )
    }

    var body: some View {
        PlaybackVersionCards(model: model)
            .alert(
                "CineLark",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.dismissError() } }
                )
            ) {
                Button(language.localized("general.dismiss"), role: .cancel) {
                    model.dismissError()
                }
            } message: {
                Text(language.userFacingError(model.errorMessage))
            }
    }
}

private struct SeasonPill: View {
    @Environment(\.appLanguage) private var language
    let season: Season
    let isSelected: Bool
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if isSelected {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityLabel(season.title)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .controlSize(.large)
                .accessibilityLabel(season.title)
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            Text(season.title)
                .font(.headline)
            if season.userState.played {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if season.userState.progress > 0 {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct EpisodePill: View {
    @Environment(\.appLanguage) private var language
    let episode: Episode
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(episode.number))
                .font(.headline.monospacedDigit())
                .foregroundStyle(isCurrent ? .black : .primary)
                .frame(width: 56, height: 48)
                .background(
                    isCurrent ? Color.accentColor : Color.white.opacity(0.065),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isCurrent ? Color.accentColor : Color.white.opacity(0.14),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) {
                    if episode.userState.played {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(isCurrent ? .black.opacity(0.72) : .green)
                            .padding(4)
                    } else if episode.userState.progress > 0 {
                        Circle()
                            .fill(isCurrent ? .black.opacity(0.72) : Color.accentColor)
                            .frame(width: 7, height: 7)
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if episode.userState.progress > 0 {
                        ProgressView(
                            value: episode.userState.played ? 1 : episode.userState.progress
                        )
                        .progressViewStyle(.linear)
                        .tint(episode.userState.played ? .green : Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.bottom, 4)
                    }
                }
        }
        .buttonStyle(CineLarkPressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let number = language.localized("episode.number", String(episode.number))
        if episode.userState.played {
            return "\(number), \(language.localized("episode.watched"))"
        }
        if episode.userState.progress > 0 {
            let progress = language.localized(
                "episode.watched_progress",
                language.progressPercent(episode.userState.progress),
                language.playbackTimestamp(episode.userState.positionSeconds)
            )
            return "\(number), \(progress)"
        }
        return number
    }
}

private struct EpisodeRow: View {
    @Environment(\.appLanguage) private var language
    let episode: Episode
    let action: () -> Void
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

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
                            .glassEffect(.regular, in: Capsule())
                            .padding(8)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if episode.userState.progress > 0 {
                            ProgressView(value: episode.userState.played ? 1 : episode.userState.progress)
                                .progressViewStyle(.linear)
                                .tint(episode.userState.played ? .green : Color.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 7)
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
                    if episode.userState.played {
                        Label(
                            language.localized("episode.watched"),
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                    } else if episode.userState.progress > 0 {
                        Text(
                            language.localized(
                                "episode.watched_progress",
                                language.progressPercent(episode.userState.progress),
                                language.playbackTimestamp(episode.userState.positionSeconds)
                            )
                        )
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.yellow)
                    }
                }

                Spacer(minLength: 16)

                Image(systemName: "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 40)
                    .glassEffect(
                        .regular.tint(.blue).interactive(),
                        in: Capsule()
                    )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CineLarkPressButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .background(
            Color.white.opacity(isHovering || isFocused ? 0.10 : 0.05),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .cineLarkFocusSurface(
            isActive: isHovering || isFocused,
            cornerRadius: 16,
            scale: 1.01
        )
        .onHover { isHovering = $0 }
        .accessibilityLabel(episodeAccessibilityLabel)
        .accessibilityHint(language.localized("episode.choose_hint"))
    }

    private var episodeAccessibilityLabel: String {
        var label = language.localized(
            "episode.accessibility_label",
            language.localized("episode.number", String(episode.number)),
            episode.title
        )
        if episode.userState.played {
            label += ", \(language.localized("episode.watched"))"
        } else if episode.userState.progress > 0 {
            let progress = language.localized(
                "episode.watched_progress",
                language.progressPercent(episode.userState.progress),
                language.playbackTimestamp(episode.userState.positionSeconds)
            )
            label += ", \(progress)"
        }
        return label
    }
}
