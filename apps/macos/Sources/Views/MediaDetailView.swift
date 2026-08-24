import SwiftUI
import CineLarkDomain

struct MediaDetailView: View {
    private enum KeyboardTarget: Hashable {
        case primaryPlayback
        case favorite
        case movieAsset(String)
        case season(String)
        case episode(String)
        case showMore
        case person(String)
    }

    private enum KeyboardSectionAxis: Equatable {
        case horizontal
        case vertical
    }

    private struct KeyboardSection {
        let id: String
        let axis: KeyboardSectionAxis
        let targets: [KeyboardTarget]
    }

    @Environment(\.appLanguage) private var language
    @Environment(\.mediaTransitionNamespace) private var transitionNamespace
    @Environment(ShortcutCoordinator.self) private var shortcuts
    @State private var model: MediaDetailModel
    @State private var playbackOptions: PlaybackOptionsContext? = nil
    @State private var showsAllEpisodes = false
    @State private var keyboardSelection: KeyboardTarget?
    @State private var rememberedKeyboardSelections: [String: KeyboardTarget] = [:]
    @State private var pointerSelection: KeyboardTarget?
    @State private var visibleKeyboardSectionIDs: Set<String> = []
    @State private var visibleKeyboardTargets: Set<KeyboardTarget> = []
    @State private var keyboardOwner = UUID()
    @State private var episodeExpansionFocusTask: Task<Void, Never>?
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
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34) {
                    hero
                        .id(Self.heroSectionID)
                        .onScrollVisibilityChange(threshold: 0.15) { visible in
                            updateKeyboardSectionVisibility(
                                Self.heroSectionID,
                                visible: visible
                            )
                        }

                    if model.item.kind == .movie {
                        movieVersions
                            .id(Self.movieVersionsSectionID)
                            .onScrollVisibilityChange(threshold: 0.15) { visible in
                                updateKeyboardSectionVisibility(
                                    Self.movieVersionsSectionID,
                                    visible: visible
                                )
                            }
                    } else {
                        seriesContent
                    }

                    if let detail = model.detail, !credits(in: detail).isEmpty {
                        cast(credits(in: detail))
                            .id(Self.castSectionID)
                            .onScrollVisibilityChange(threshold: 0.15) { visible in
                                updateKeyboardSectionVisibility(
                                    Self.castSectionID,
                                    visible: visible
                                )
                            }
                    }
                }
                .padding(.bottom, 48)
            }
            .onScrollTargetVisibilityChange(
                idType: String.self,
                threshold: 0.15
            ) { ids in
                updateVisibleEpisodeTargets(ids)
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
            .onAppear {
                registerKeyboardNavigation(scrollProxy: scrollProxy)
            }
            .onDisappear {
                episodeExpansionFocusTask?.cancel()
                pointerSelection = nil
                visibleKeyboardSectionIDs = []
                visibleKeyboardTargets = []
                shortcuts.removeNavigationSurface(owner: keyboardOwner)
            }
            .onChange(of: keyboardSignature) {
                reconcileKeyboardSelection()
                registerKeyboardNavigation(scrollProxy: scrollProxy)
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
                url: model.heroBackdropURL ?? model.heroPosterURL,
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
                    .focusEffectDisabled()
                    .cineLarkFocusSurface(
                        isActive: visibleKeyboardSelection == .primaryPlayback,
                        cornerRadius: 22,
                        scale: 1.02
                    )
                    .cineLarkPointerSelection { hovering in
                        updatePointerSelection(.primaryPlayback, hovering: hovering)
                    }
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
                .focusEffectDisabled()
                .cineLarkFocusSurface(
                    isActive: visibleKeyboardSelection == .favorite,
                    cornerRadius: 22,
                    scale: 1.02
                )
                .cineLarkPointerSelection { hovering in
                    updatePointerSelection(.favorite, hovering: hovering)
                }

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
                    playback: model.playback,
                    selectedAssetID: selectedMovieAssetID,
                    onPointerSelection: { assetID, hovering in
                        updatePointerSelection(
                            .movieAsset(assetID),
                            hovering: hovering
                        )
                    }
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
                LazyVStack(spacing: 0) {
                    ForEach(visibleEpisodes) { episode in
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: CineLarkDesign.Layout.focusScrollClearance)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)

                            EpisodeRow(
                                episode: episode,
                                isKeyboardSelected: visibleKeyboardSelection == .episode(episode.id),
                                isKeyboardNavigationActive: visibleKeyboardSelection != nil,
                                onPointerSelection: { hovering in
                                    updatePointerSelection(
                                        .episode(episode.id),
                                        hovering: hovering
                                    )
                                }
                            ) {
                                presentEpisodeOptions(episode)
                            }
                        }
                        .id(episodeScrollID(episode.id))
                    }
                }
                .scrollTargetLayout()
                .focusSection()

                if model.episodes.count > Self.collapsedEpisodeCount {
                    Button {
                        visibleKeyboardTargets.remove(.showMore)
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
                    .focusEffectDisabled()
                    .cineLarkFocusSurface(
                        isActive: visibleKeyboardSelection == .showMore,
                        cornerRadius: 16,
                        scale: 1.01
                    )
                    .cineLarkPointerSelection { hovering in
                        updatePointerSelection(.showMore, hovering: hovering)
                    }
                    .id(Self.showMoreScrollID)
                    .onScrollVisibilityChange(threshold: 0.15) { visible in
                        updateKeyboardTargetVisibility(.showMore, visible: visible)
                    }
                }
            }
        }
        .padding(.horizontal, 40)
        .id(Self.episodesSectionID)
        .onChange(of: model.selectedSeasonID) {
            episodeExpansionFocusTask?.cancel()
            showsAllEpisodes = false
        }
    }

    private static let collapsedEpisodeCount = 6

    private var visibleEpisodes: [Episode] {
        guard !showsAllEpisodes else { return model.episodes }
        return Array(model.episodes.prefix(Self.collapsedEpisodeCount))
    }

    private var seasonStrip: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(model.seasons) { season in
                        SeasonPill(
                            season: season,
                            isSelected: model.selectedSeasonID == season.id,
                            isKeyboardSelected: visibleKeyboardSelection == .season(season.id),
                            onPointerSelection: { hovering in
                                updatePointerSelection(
                                    .season(season.id),
                                    hovering: hovering
                                )
                            }
                        ) {
                            Task { await model.selectSeason(season.id) }
                        }
                        .id(season.id)
                    }
                }
                .focusSection()
                .padding(.vertical, 4)
                .cineLarkHorizontalScrollIndicatorsHidden()
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedSeasonID) {
                guard let selectedSeasonID else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollProxy.scrollTo(selectedSeasonID, anchor: .leading)
                }
            }
        }
        .id(Self.seasonsSectionID)
        .onScrollVisibilityChange(threshold: 0.15) { visible in
            updateKeyboardSectionVisibility(Self.seasonsSectionID, visible: visible)
        }
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

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 20) {
                        ForEach(Array(people.prefix(36))) { person in
                            PersonCreditLink(
                                person: person,
                                isKeyboardSelected: visibleKeyboardSelection == .person(person.id),
                                isKeyboardNavigationActive: visibleKeyboardSelection != nil,
                                onPointerSelection: { hovering in
                                    updatePointerSelection(
                                        .person(person.id),
                                        hovering: hovering
                                    )
                                }
                            )
                            .id(person.id)
                        }
                    }
                    .focusSection()
                    .cineLarkHorizontalScrollIndicatorsHidden()
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedPersonID) {
                    guard let selectedPersonID else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo(selectedPersonID, anchor: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, 40)
    }

    private func credits(in detail: MediaDetail) -> [PersonCredit] {
        var seen: Set<String> = []
        return (detail.directors + detail.cast).filter { seen.insert($0.id).inserted }
    }

    private static let heroSectionID = "detail.hero"
    private static let movieVersionsSectionID = "detail.versions"
    private static let seasonsSectionID = "detail.seasons"
    private static let episodesSectionID = "detail.episodes"
    private static let castSectionID = "detail.cast"
    private static let showMoreScrollID = "detail.episodes.more"
    private static let episodeScrollIDPrefix = "detail.episode."

    private var keyboardSections: [KeyboardSection] {
        var sections = [
            KeyboardSection(
                id: Self.heroSectionID,
                axis: .horizontal,
                targets: [.primaryPlayback, .favorite]
            )
        ]
        if model.item.kind == .movie, !model.movieAssets.isEmpty {
            sections.append(
                KeyboardSection(
                    id: Self.movieVersionsSectionID,
                    axis: .vertical,
                    targets: model.movieAssets.map { .movieAsset($0.id) }
                )
            )
        }
        if model.item.kind == .series {
            if !model.seasons.isEmpty {
                sections.append(
                    KeyboardSection(
                        id: Self.seasonsSectionID,
                        axis: .horizontal,
                        targets: model.seasons.map { .season($0.id) }
                    )
                )
            }
            if !model.isLoadingEpisodes {
                var episodeTargets = visibleEpisodes.map { KeyboardTarget.episode($0.id) }
                if model.episodes.count > Self.collapsedEpisodeCount {
                    episodeTargets.append(.showMore)
                }
                if !episodeTargets.isEmpty {
                    sections.append(
                        KeyboardSection(
                            id: Self.episodesSectionID,
                            axis: .vertical,
                            targets: episodeTargets
                        )
                    )
                }
            }
        }
        if let detail = model.detail {
            let people = Array(credits(in: detail).prefix(36))
            if !people.isEmpty {
                sections.append(
                    KeyboardSection(
                        id: Self.castSectionID,
                        axis: .horizontal,
                        targets: people.map { .person($0.id) }
                    )
                )
            }
        }
        return sections
    }

    private var keyboardSignature: [String] {
        keyboardSections.flatMap { section in
            [section.id] + section.targets.map { String(describing: $0) }
        }
    }

    private var selectedMovieAssetID: String? {
        guard case .movieAsset(let id) = visibleKeyboardSelection else { return nil }
        return id
    }

    private var selectedSeasonID: String? {
        guard case .season(let id) = visibleKeyboardSelection else { return nil }
        return id
    }

    private var selectedPersonID: String? {
        guard case .person(let id) = visibleKeyboardSelection else { return nil }
        return id
    }

    private var visibleKeyboardSelection: KeyboardTarget? {
        playbackOptions == nil && shortcuts.usesKeyboardNavigation
            ? keyboardSelection
            : nil
    }

    private func episodeScrollID(_ episodeID: String) -> String {
        "\(Self.episodeScrollIDPrefix)\(episodeID)"
    }

    private func registerKeyboardNavigation(scrollProxy: ScrollViewProxy) {
        let sections = keyboardSections
        let selection = $keyboardSelection
        let rememberedSelections = $rememberedKeyboardSelections
        let pointerSelection = $pointerSelection
        let visibleSectionIDs = $visibleKeyboardSectionIDs
        let visibleTargets = $visibleKeyboardTargets
        shortcuts.setNavigationSurface(
            owner: keyboardOwner,
            handoffToKeyboard: {
                guard let pointerTarget = pointerSelection.wrappedValue,
                      sections.contains(where: {
                          $0.targets.contains(pointerTarget)
                      }),
                      isNavigationTargetVisible(
                          pointerTarget,
                          sections: sections,
                          visibleSectionIDs: visibleSectionIDs.wrappedValue,
                          visibleTargets: visibleTargets.wrappedValue
                      ) else {
                    return
                }
                selection.wrappedValue = pointerTarget
                if let section = sections.first(where: {
                    $0.targets.contains(pointerTarget)
                }) {
                    rememberedSelections.wrappedValue[section.id] = pointerTarget
                }
            },
            move: { direction in
                moveKeyboardSelection(
                    direction,
                    sections: sections,
                    selection: selection,
                    rememberedSelections: rememberedSelections,
                    startingTarget: shortcuts.inputModality == .pointer
                        ? pointerSelection.wrappedValue
                        : nil,
                    visibleSectionIDs: visibleSectionIDs.wrappedValue,
                    visibleTargets: visibleTargets.wrappedValue,
                    scrollProxy: scrollProxy
                )
            },
            activate: {
                activateKeyboardSelection(
                    shortcuts.inputModality == .pointer
                        ? pointerSelection.wrappedValue ?? selection.wrappedValue
                        : selection.wrappedValue,
                    selection: selection,
                    rememberedSelections: rememberedSelections,
                    scrollProxy: scrollProxy
                )
            }
        )
    }

    private func moveKeyboardSelection(
        _ direction: CineLarkFocusDirection,
        sections: [KeyboardSection],
        selection: Binding<KeyboardTarget?>,
        rememberedSelections: Binding<[String: KeyboardTarget]>,
        startingTarget: KeyboardTarget?,
        visibleSectionIDs: Set<String>,
        visibleTargets: Set<KeyboardTarget>,
        scrollProxy: ScrollViewProxy
    ) -> Bool {
        guard let firstSection = sections.first,
              let firstTarget = firstSection.targets.first else {
            return false
        }
        let current = navigationOrigin(
            for: direction,
            candidate: startingTarget ?? selection.wrappedValue,
            sections: sections,
            rememberedSelections: rememberedSelections.wrappedValue,
            visibleSectionIDs: visibleSectionIDs,
            visibleTargets: visibleTargets
        )
        guard let current,
              let sectionIndex = sections.firstIndex(where: { $0.targets.contains(current) }),
              let targetIndex = sections[sectionIndex].targets.firstIndex(of: current) else {
            selectKeyboardTarget(
                firstTarget,
                sectionID: firstSection.id,
                selection: selection,
                rememberedSelections: rememberedSelections,
                scrollProxy: scrollProxy
            )
            return true
        }

        let section = sections[sectionIndex]
        let movesWithinSection =
            (section.axis == .horizontal && (direction == .left || direction == .right)) ||
            (section.axis == .vertical && (direction == .up || direction == .down))
        if movesWithinSection {
            let delta = (direction == .left || direction == .up) ? -1 : 1
            let nextIndex = targetIndex + delta
            if section.targets.indices.contains(nextIndex) {
                selectKeyboardTarget(
                    section.targets[nextIndex],
                    sectionID: section.id,
                    selection: selection,
                    rememberedSelections: rememberedSelections,
                    scrollProxy: scrollProxy
                )
                return true
            }
        }

        let movesToPreviousSection = direction == .up ||
            (section.axis == .vertical && direction == .left)
        let movesToNextSection = direction == .down ||
            (section.axis == .vertical && direction == .right)
        guard movesToPreviousSection || movesToNextSection else { return true }
        let nextSectionIndex = movesToPreviousSection
            ? max(0, sectionIndex - 1)
            : min(sections.count - 1, sectionIndex + 1)
        let nextSection = sections[nextSectionIndex]
        let nextTarget: KeyboardTarget
        if nextSectionIndex == sectionIndex {
            nextTarget = section.targets[targetIndex]
        } else if let rememberedTarget = rememberedSelections.wrappedValue[nextSection.id],
                  nextSection.targets.contains(rememberedTarget) {
            nextTarget = rememberedTarget
        } else if let firstTarget = nextSection.targets.first {
            nextTarget = firstTarget
        } else {
            return false
        }
        selectKeyboardTarget(
            nextTarget,
            sectionID: nextSection.id,
            selection: selection,
            rememberedSelections: rememberedSelections,
            scrollProxy: scrollProxy
        )
        return true
    }

    private func navigationOrigin(
        for direction: CineLarkFocusDirection,
        candidate: KeyboardTarget?,
        sections: [KeyboardSection],
        rememberedSelections: [String: KeyboardTarget],
        visibleSectionIDs: Set<String>,
        visibleTargets: Set<KeyboardTarget>
    ) -> KeyboardTarget? {
        guard !visibleSectionIDs.isEmpty || !visibleTargets.isEmpty else {
            return candidate
        }
        if let candidate,
           isNavigationTargetVisible(
               candidate,
               sections: sections,
               visibleSectionIDs: visibleSectionIDs,
               visibleTargets: visibleTargets
           ) {
            return candidate
        }

        let orderedVisibleTargets = sections.flatMap { section -> [KeyboardTarget] in
            if section.id == Self.episodesSectionID {
                return section.targets.filter { visibleTargets.contains($0) }
            }
            guard visibleSectionIDs.contains(section.id) else { return [] }
            if let rememberedTarget = rememberedSelections[section.id],
               section.targets.contains(rememberedTarget) {
                return [rememberedTarget]
            }
            return Array(section.targets.prefix(1))
        }
        guard !orderedVisibleTargets.isEmpty else { return candidate }
        return direction == .down
            ? orderedVisibleTargets.last
            : orderedVisibleTargets.first
    }

    private func isNavigationTargetVisible(
        _ target: KeyboardTarget,
        sections: [KeyboardSection],
        visibleSectionIDs: Set<String>,
        visibleTargets: Set<KeyboardTarget>
    ) -> Bool {
        guard !visibleSectionIDs.isEmpty || !visibleTargets.isEmpty,
              let section = sections.first(where: { $0.targets.contains(target) }) else {
            return true
        }
        if section.id == Self.episodesSectionID {
            return visibleTargets.contains(target)
        }
        return visibleSectionIDs.contains(section.id)
    }

    private func selectKeyboardTarget(
        _ target: KeyboardTarget,
        sectionID: String,
        selection: Binding<KeyboardTarget?>,
        rememberedSelections: Binding<[String: KeyboardTarget]>,
        scrollProxy: ScrollViewProxy
    ) {
        let scrollID: String
        switch target {
        case .movieAsset(let id):
            scrollID = movieAssetScrollID(id)
        case .episode(let id):
            scrollID = episodeScrollID(id)
        case .showMore:
            scrollID = Self.showMoreScrollID
        default:
            scrollID = sectionID
        }
        withAnimation(.easeOut(duration: 0.2)) {
            selection.wrappedValue = target
            rememberedSelections.wrappedValue[sectionID] = target
            scrollProxy.scrollTo(scrollID, anchor: .top)
        }
    }

    private func movieAssetScrollID(_ assetID: String) -> String {
        "detail.version.\(assetID)"
    }

    private func activateKeyboardSelection(
        _ target: KeyboardTarget?,
        selection: Binding<KeyboardTarget?>,
        rememberedSelections: Binding<[String: KeyboardTarget]>,
        scrollProxy: ScrollViewProxy
    ) -> Bool {
        guard let target else { return false }
        switch target {
        case .primaryPlayback:
            guard model.canStartPlayback, !model.isStartingPlayback else { return false }
            Task { await model.playPrimary() }
            return true
        case .favorite:
            guard !model.isUpdatingFavorite,
                  !model.isFavorite || model.canRemoveFavorite else {
                return false
            }
            Task { await model.toggleFavorite() }
            return true
        case .movieAsset(let id):
            guard let asset = model.movieAssets.first(where: { $0.id == id }) else {
                return false
            }
            Task { await model.playMovieAsset(asset) }
            return true
        case .season(let id):
            guard model.seasons.contains(where: { $0.id == id }) else { return false }
            Task { await model.selectSeason(id) }
            return true
        case .episode(let id):
            guard let episode = visibleEpisodes.first(where: { $0.id == id }) else {
                return false
            }
            presentEpisodeOptions(episode)
            return true
        case .showMore:
            let isExpanding = !showsAllEpisodes
            let destinationEpisode = isExpanding
                ? model.episodes.dropFirst(Self.collapsedEpisodeCount).first
                : model.episodes.prefix(Self.collapsedEpisodeCount).last
            visibleKeyboardTargets.remove(.showMore)
            showsAllEpisodes.toggle()
            guard let destinationEpisode else { return true }
            let destination = KeyboardTarget.episode(destinationEpisode.id)
            selection.wrappedValue = destination
            rememberedSelections.wrappedValue[Self.episodesSectionID] = destination
            episodeExpansionFocusTask?.cancel()
            episodeExpansionFocusTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollProxy.scrollTo(
                        episodeScrollID(destinationEpisode.id),
                        anchor: .top
                    )
                }
            }
            return true
        case .person(let id):
            guard let detail = model.detail,
                  let person = credits(in: detail).first(where: { $0.id == id }) else {
                return false
            }
            return shortcuts.openPerson(person)
        }
    }

    private func reconcileKeyboardSelection() {
        let sectionsByID = Dictionary(
            uniqueKeysWithValues: keyboardSections.map { ($0.id, $0.targets) }
        )
        let validSectionIDs = Set(sectionsByID.keys)
        let validTargets = Set(sectionsByID.values.flatMap { $0 })
        rememberedKeyboardSelections = rememberedKeyboardSelections.filter {
            sectionsByID[$0.key]?.contains($0.value) == true
        }
        visibleKeyboardSectionIDs.formIntersection(validSectionIDs)
        visibleKeyboardTargets.formIntersection(validTargets)
        if let keyboardSelection,
           !keyboardSections.contains(where: { $0.targets.contains(keyboardSelection) }) {
            self.keyboardSelection = nil
        }
        if let pointerSelection,
           !keyboardSections.contains(where: { $0.targets.contains(pointerSelection) }) {
            self.pointerSelection = nil
        }
    }

    private func updateKeyboardSectionVisibility(_ sectionID: String, visible: Bool) {
        if visible {
            visibleKeyboardSectionIDs.insert(sectionID)
        } else {
            visibleKeyboardSectionIDs.remove(sectionID)
        }
    }

    private func updateKeyboardTargetVisibility(_ target: KeyboardTarget, visible: Bool) {
        if visible {
            visibleKeyboardTargets.insert(target)
        } else {
            visibleKeyboardTargets.remove(target)
        }
    }

    private func updateVisibleEpisodeTargets(_ ids: [String]) {
        let episodeTargets = Set(ids.compactMap { id -> KeyboardTarget? in
            guard id.hasPrefix(Self.episodeScrollIDPrefix) else { return nil }
            return .episode(String(id.dropFirst(Self.episodeScrollIDPrefix.count)))
        })
        let showMoreIsVisible = visibleKeyboardTargets.contains(.showMore)
        visibleKeyboardTargets = episodeTargets
        if showMoreIsVisible {
            visibleKeyboardTargets.insert(.showMore)
        }
    }

    private func updatePointerSelection(
        _ target: KeyboardTarget,
        hovering: Bool
    ) {
        if hovering {
            pointerSelection = target
        } else if pointerSelection == target {
            pointerSelection = nil
        }
    }
}

private struct PersonCreditLink: View {
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let person: PersonCredit
    let isKeyboardSelected: Bool
    let isKeyboardNavigationActive: Bool
    let onPointerSelection: (Bool) -> Void
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
                    isActive: isActive,
                    cornerRadius: 52,
                    scale: 1.06
                )
                .cineLarkKeyboardSelectionHint(isActive: isKeyboardSelected)
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
        .onHover { hovering in
            isHovering = hovering
            if !hovering || shortcuts.inputModality == .pointer {
                onPointerSelection(hovering)
            }
        }
        .onChange(of: shortcuts.inputModality) {
            if shortcuts.inputModality == .pointer, isHovering {
                onPointerSelection(true)
            }
        }
        .onDisappear {
            if isHovering { onPointerSelection(false) }
        }
    }

    private var isActive: Bool {
        switch shortcuts.inputModality {
        case .pointer:
            isHovering
        case .keyboard:
            isKeyboardSelected || (!isKeyboardNavigationActive && isFocused)
        }
    }
}

private struct InlineMovieVersionsView: View {
    @Environment(\.appLanguage) private var language
    @State private var model: PlaybackOptionsModel
    let selectedAssetID: String?
    let onPointerSelection: (String, Bool) -> Void

    init(
        context: PlaybackOptionsContext,
        playback: PlaybackCoordinator,
        selectedAssetID: String? = nil,
        onPointerSelection: @escaping (String, Bool) -> Void
    ) {
        self.selectedAssetID = selectedAssetID
        self.onPointerSelection = onPointerSelection
        _model = State(
            initialValue: PlaybackOptionsModel(
                context: context,
                playback: playback
            )
        )
    }

    var body: some View {
        PlaybackVersionCards(
            model: model,
            selectedAssetID: selectedAssetID,
            onPointerSelection: onPointerSelection,
            scrollID: { "detail.version.\($0)" }
        )
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
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let season: Season
    let isSelected: Bool
    let isKeyboardSelected: Bool
    let onPointerSelection: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Group {
            if isSelected {
                Button(action: action) { label }
                    .buttonStyle(.glassProminent)
                    .accessibilityAddTraits(.isSelected)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.glass)
            }
        }
        .controlSize(.large)
        .accessibilityLabel(season.title)
        .focusEffectDisabled()
        .cineLarkFocusSurface(
            isActive: shortcuts.usesKeyboardNavigation && isKeyboardSelected,
            cornerRadius: 18,
            scale: 1.02
        )
        .cineLarkPointerSelection(onPointerSelection)
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
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let episode: Episode
    let isKeyboardSelected: Bool
    let isKeyboardNavigationActive: Bool
    let onPointerSelection: (Bool) -> Void
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
            Color.white.opacity(isActive ? 0.10 : 0.05),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .cineLarkFocusSurface(
            isActive: isActive,
            cornerRadius: 16,
            scale: 1.01
        )
        .cineLarkKeyboardSelectionHint(isActive: isKeyboardSelected)
        .onHover { hovering in
            isHovering = hovering
            if !hovering || shortcuts.inputModality == .pointer {
                onPointerSelection(hovering)
            }
        }
        .onChange(of: shortcuts.inputModality) {
            if shortcuts.inputModality == .pointer, isHovering {
                onPointerSelection(true)
            }
        }
        .onDisappear {
            if isHovering { onPointerSelection(false) }
        }
        .accessibilityLabel(episodeAccessibilityLabel)
        .accessibilityHint(language.localized("episode.choose_hint"))
    }

    private var isActive: Bool {
        switch shortcuts.inputModality {
        case .pointer:
            isHovering
        case .keyboard:
            isKeyboardSelected || (!isKeyboardNavigationActive && isFocused)
        }
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
