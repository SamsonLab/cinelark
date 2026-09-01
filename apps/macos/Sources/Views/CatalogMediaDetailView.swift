import SwiftUI
import ComposableArchitecture
import CineLarkDomain
import CineLarkPluginAPI

enum CineLarkNavigationOriginPolicy {
    static func resolve<T: Hashable>(
        candidate: T?,
        isCandidateVisible: Bool,
        rebasesOffscreenCandidate: Bool,
        orderedVisibleCandidates: [T],
        direction: CineLarkFocusDirection
    ) -> T? {
        if let candidate, !rebasesOffscreenCandidate || isCandidateVisible {
            return candidate
        }
        guard !orderedVisibleCandidates.isEmpty else { return candidate }
        return direction == .down
            ? orderedVisibleCandidates.last
            : orderedVisibleCandidates.first
    }
}

struct CatalogMediaDetailView: View {
    private enum KeyboardTarget: Hashable {
        case primaryPlayback
        case favorite
        case movieVariant(String)
        case season(String)
        case episode(String)
        case showMore
        case person(String)
    }

    private enum KeyboardSectionAxis {
        case horizontal
        case vertical
    }

    private struct KeyboardSection {
        let id: String
        let axis: KeyboardSectionAxis
        let targets: [KeyboardTarget]
    }

    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    @Bindable var store: StoreOf<MediaDetailFeature>
    let transitionID: UUID?
    @State private var showsAllEpisodes = false
    @State private var expandedMovieVariantID: String?
    @State private var keyboardSelection: KeyboardTarget?
    @State private var rememberedKeyboardSelections: [String: KeyboardTarget] = [:]
    @State private var pointerSelection: KeyboardTarget?
    @State private var visibleKeyboardSectionIDs: Set<String> = []
    @State private var visibleKeyboardTargets: Set<KeyboardTarget> = []
    @State private var keyboardOwner = UUID()
    @State private var episodeExpansionFocusTask: Task<Void, Never>?

    init(store: StoreOf<MediaDetailFeature>, transitionID: UUID? = nil) {
        self.store = store
        self.transitionID = transitionID
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34) {
                    hero
                        .id(Self.heroSectionID)
                        .onScrollVisibilityChange(threshold: 0.15) { visible in
                            updateKeyboardSectionVisibility(Self.heroSectionID, visible: visible)
                        }

                    if store.item.kind == .movie {
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

                    if let detail = store.detail {
                        let credits = uniqueCredits(in: detail)
                        if !credits.isEmpty {
                            peopleSection(credits)
                                .id(Self.peopleSectionID)
                                .onScrollVisibilityChange(threshold: 0.15) { visible in
                                    updateKeyboardSectionVisibility(
                                        Self.peopleSectionID,
                                        visible: visible
                                    )
                                }
                        }
                    }

                    if let failure = store.failure {
                        Label(
                            language.userFacingError(String(describing: failure)),
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.red)
                        .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
                    }
                }
                .padding(.bottom, 48)
            }
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.15) { ids in
                updateVisibleEpisodeTargets(ids)
            }
            .onAppear { registerKeyboardNavigation(scrollProxy: scrollProxy) }
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
        .background(CineLarkPageBackground())
        .navigationTitle(store.item.title)
        .task { store.send(.view(.appeared)) }
        .sheet(
            item: $store.scope(
                state: \.playbackOptions,
                action: \.playbackOptions
            )
        ) { optionsStore in
            CatalogPlaybackOptionsView(store: optionsStore)
        }
        .onChange(of: store.selectedSeasonID) {
            episodeExpansionFocusTask?.cancel()
            showsAllEpisodes = false
        }
    }

    private var hero: some View {
        ZStack(alignment: .top) {
            CineLarkCinematicBackdrop(
                url: store.item.backdropURL ?? store.item.posterURL,
                height: 620,
                leadingShade: 0.90
            )

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(language.localized(
                        store.item.kind == .movie ? "detail.movie" : "detail.series"
                    ))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.accentColor)

                    Text(store.item.title)
                        .font(CineLarkDesign.Typography.heroTitle)
                        .lineLimit(2)
                        .help(store.item.title)

                    if let originalTitle {
                        Text(originalTitle)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 100)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CineLarkDesign.Layout.contentMargin)

                HStack(alignment: .top, spacing: 36) {
                    MediaArtworkSurface(
                        item: store.item,
                        url: store.item.posterURL ?? store.item.backdropURL,
                        locator: store.locator,
                        size: CGSize(width: 250, height: 375),
                        role: .playback,
                        transitionID: transitionID,
                        isTransitionSource: false
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
                .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
                .padding(.top, 34)
            }
        }
    }

    private var heroMetadata: some View {
        VStack(alignment: .leading, spacing: 16) {
            MediaFacts(
                item: store.item,
                fields: .extended,
                spacing: 14,
                font: .body
            )

            if !store.item.genres.isEmpty {
                HStack(spacing: 9) {
                    ForEach(store.item.genres.prefix(5)) { genre in
                        Text(genre.name)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .overlay { Capsule().stroke(Color.white.opacity(0.18)) }
                    }
                }
            }

            if let synopsis = store.item.synopsis, !synopsis.isEmpty {
                Text(synopsis)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .lineSpacing(4)
                    .frame(maxWidth: 900, alignment: .leading)
            }

            playbackSummary

            HStack(spacing: 12) {
                Button {
                    store.send(.view(.playPrimary))
                } label: {
                    if store.isLoading && !store.canPlayPrimary {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(primaryPlaybackLabel, systemImage: "play.fill")
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .disabled(!store.canPlayPrimary)
                .focusEffectDisabled()
                .cineLarkFocusSurface(
                    isActive: visibleKeyboardSelection == .primaryPlayback,
                    cornerRadius: 22,
                    scale: 1.02
                )
                .cineLarkPointerSelection { hovering in
                    updatePointerSelection(.primaryPlayback, hovering: hovering)
                }

                Button {
                    store.send(.view(.toggleFavorite))
                } label: {
                    if store.isUpdatingFavorite {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(
                            language.localized(
                                store.isFavorite ? "detail.favorite" : "detail.add_favorite"
                            ),
                            systemImage: store.isFavorite ? "heart.fill" : "heart"
                        )
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.extraLarge)
                .tint(store.isFavorite ? .orange : .accentColor)
                .disabled(store.isUpdatingFavorite)
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
        if store.item.kind == .series,
           let resume = store.resumableSeriesItem {
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
        if store.item.userState.played {
            Label(language.localized("detail.watched"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .glassEffect(.regular, in: Capsule())
        } else if store.item.userState.progress > 0 || store.resumableSeriesItem != nil {
            Label(language.localized("detail.watching"), systemImage: "eye.fill")
                .foregroundStyle(.yellow)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .glassEffect(.regular, in: Capsule())
        }
    }

    private var primaryPlaybackLabel: String {
        if store.item.kind == .series, let target = store.primarySeriesItem {
            if target.userState.positionSeconds > 0 && !target.userState.played {
                return language.localized(
                    "detail.continue_episode",
                    episodeDescriptor(target),
                    language.progressPercent(target.userState.progress)
                )
            }
            return language.localized("detail.play_episode", episodeDescriptor(target))
        }
        if store.item.userState.played {
            return language.localized("detail.replay")
        }
        if store.item.userState.progress > 0 {
            return language.localized(
                "detail.continue",
                language.progressPercent(store.item.userState.progress)
            )
        }
        return language.localized("detail.play")
    }

    private var seriesContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(language.localized("detail.episodes"))
                    .font(.title2.bold())
                if !store.seasons.isEmpty {
                    Text(language.localized(
                        store.seasons.count == 1
                            ? "detail.season_count_one"
                            : "detail.season_count_many",
                        String(store.seasons.count)
                    ))
                    .foregroundStyle(.secondary)
                }
            }

            if !store.seasons.isEmpty {
                seasonStrip
            }

            if store.isLoadingEpisodes || (store.isLoading && store.seasons.isEmpty) {
                ProgressView(language.localized("detail.loading_episodes"))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if store.episodes.isEmpty {
                ContentUnavailableView(
                    language.localized("collection.empty"),
                    systemImage: "rectangle.stack"
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(visibleEpisodes) { episode in
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: CineLarkDesign.Layout.focusScrollClearance)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)

                            CatalogEpisodeRow(
                                episode: episode,
                                sourceID: store.locator.sourceID,
                                isKeyboardSelected: visibleKeyboardSelection ==
                                    .episode(episode.id),
                                isKeyboardNavigationActive: visibleKeyboardSelection != nil,
                                onPointerSelection: { hovering in
                                    updatePointerSelection(
                                        .episode(episode.id),
                                        hovering: hovering
                                    )
                                }
                            ) {
                                store.send(.view(.episodeSelected(episode)))
                            }
                        }
                        .id(episodeScrollID(episode.id))
                    }
                }
                .scrollTargetLayout()
                .focusSection()

                if store.episodes.count > Self.collapsedEpisodeCount {
                    Button {
                        visibleKeyboardTargets.remove(.showMore)
                        showsAllEpisodes.toggle()
                    } label: {
                        Label(
                            language.localized(
                                showsAllEpisodes ? "episode.show_less" : "episode.show_more",
                                String(store.episodes.count - Self.collapsedEpisodeCount)
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
        .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
        .id(Self.episodesSectionID)
    }

    private var movieVersions: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(language.localized("detail.versions"))
                    .font(.title2.bold())
                Spacer()
                if !store.movieVariants.isEmpty {
                    Text(language.localized(
                        "playback.available_count",
                        String(store.movieVariants.count)
                    ))
                    .foregroundStyle(.secondary)
                }
            }

            if store.isLoadingMovieVariants && store.movieVariants.isEmpty {
                ProgressView(language.localized("detail.loading_versions"))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if store.movieVariants.isEmpty {
                Text(language.localized("detail.no_versions"))
                    .foregroundStyle(.secondary)
            } else {
                PlaybackVariantCards(
                    variants: store.movieVariants,
                    expandedVariantID: expandedMovieVariantID,
                    selectedVariantID: selectedMovieVariantID,
                    onPlay: { store.send(.view(.movieVariantSelected($0))) },
                    onToggleDetails: { id in
                        expandedMovieVariantID = expandedMovieVariantID == id ? nil : id
                    },
                    onPointerSelection: { id, hovering in
                        updatePointerSelection(.movieVariant(id), hovering: hovering)
                    }
                )
            }
        }
        .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
    }

    private var seasonStrip: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(store.seasons) { season in
                        Button {
                            store.send(.view(.seasonSelected(season.id)))
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(season.title)
                                    .font(.headline)
                                Text(String(season.episodeCount))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 58)
                        }
                        .buttonStyle(.glass)
                        .tint(store.selectedSeasonID == season.id ? .accentColor : nil)
                        .focusEffectDisabled()
                        .cineLarkFocusSurface(
                            isActive: visibleKeyboardSelection == .season(season.id),
                            cornerRadius: 18,
                            scale: 1.02
                        )
                        .cineLarkPointerSelection { hovering in
                            updatePointerSelection(.season(season.id), hovering: hovering)
                        }
                        .id(season.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .cineLarkHorizontalScrollIndicatorsHidden()
            .onChange(of: store.selectedSeasonID) {
                guard let id = store.selectedSeasonID else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollProxy.scrollTo(id, anchor: .leading)
                }
            }
        }
        .id(Self.seasonsSectionID)
        .onScrollVisibilityChange(threshold: 0.15) { visible in
            updateKeyboardSectionVisibility(Self.seasonsSectionID, visible: visible)
        }
    }

    private func peopleSection(_ people: [PersonCredit]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(language.localized("detail.cast_crew"))
                .font(.title2.bold())

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 20) {
                        ForEach(Array(people.prefix(36))) { person in
                            NavigationLink(
                                state: NavigationFeature.Path.State.person(
                                    PersonRouteFeature.State(
                                        person: person,
                                        sourceID: store.locator.sourceID
                                    )
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ArtworkView(
                                        url: person.avatarURL,
                                        placeholderSystemImage: "person.fill",
                                        locator: MediaLocatorID(
                                            sourceID: store.locator.sourceID,
                                            providerItemID: person.id
                                        )
                                    )
                                    .frame(width: 150, height: 150)
                                    .clipShape(Circle())

                                    Text(person.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    if let character = person.character, !character.isEmpty {
                                        Text(character)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 150, alignment: .leading)
                            }
                            .buttonStyle(CineLarkPressButtonStyle())
                            .focusEffectDisabled()
                            .cineLarkFocusSurface(
                                isActive: visibleKeyboardSelection == .person(person.id),
                                cornerRadius: CineLarkDesign.Shape.cardRadius
                            )
                            .cineLarkPointerSelection { hovering in
                                updatePointerSelection(.person(person.id), hovering: hovering)
                            }
                            .id(person.id)
                        }
                    }
                    .focusSection()
                    .padding(.vertical, 12)
                }
                .cineLarkHorizontalScrollIndicatorsHidden()
                .onChange(of: selectedPersonID) {
                    guard let selectedPersonID else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo(selectedPersonID, anchor: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
    }

    private static let collapsedEpisodeCount = 6
    private static let heroSectionID = "detail.hero"
    private static let movieVersionsSectionID = "detail.versions"
    private static let seasonsSectionID = "detail.seasons"
    private static let episodesSectionID = "detail.episodes"
    private static let peopleSectionID = "detail.people"
    private static let episodeScrollIDPrefix = "detail.episode."
    private static let showMoreScrollID = "detail.showMore"

    private var visibleEpisodes: [Episode] {
        showsAllEpisodes
            ? store.episodes
            : Array(store.episodes.prefix(Self.collapsedEpisodeCount))
    }

    private var originalTitle: String? {
        guard let value = store.item.originalTitle,
              !value.isEmpty,
              value.caseInsensitiveCompare(store.item.title) != .orderedSame
        else { return nil }
        return value
    }

    private func episodeDescriptor(_ episode: Episode) -> String {
        let seasonNumber = store.seasons.first { $0.id == episode.seasonID }?.number
        if let seasonNumber {
            return language.localized(
                "episode.season_episode",
                String(seasonNumber),
                String(episode.number)
            )
        }
        return language.localized("episode.number", String(episode.number))
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
        if let episode = store.episodes.first(where: { $0.id == item.item.id }) {
            return episodeDescriptor(episode)
        }
        return item.subtitle ?? item.title
    }

    private var keyboardSections: [KeyboardSection] {
        var sections: [KeyboardSection] = [
            KeyboardSection(
                id: Self.heroSectionID,
                axis: .horizontal,
                targets: [.primaryPlayback, .favorite]
            )
        ]
        if store.item.kind == .movie, !store.movieVariants.isEmpty {
            sections.append(
                KeyboardSection(
                    id: Self.movieVersionsSectionID,
                    axis: .vertical,
                    targets: store.movieVariants.map { .movieVariant($0.id) }
                )
            )
        }
        if store.item.kind == .series {
            if !store.seasons.isEmpty {
                sections.append(
                    KeyboardSection(
                        id: Self.seasonsSectionID,
                        axis: .horizontal,
                        targets: store.seasons.map { .season($0.id) }
                    )
                )
            }
            if !store.isLoadingEpisodes {
                var targets = visibleEpisodes.map { KeyboardTarget.episode($0.id) }
                if store.episodes.count > Self.collapsedEpisodeCount {
                    targets.append(.showMore)
                }
                if !targets.isEmpty {
                    sections.append(
                        KeyboardSection(
                            id: Self.episodesSectionID,
                            axis: .vertical,
                            targets: targets
                        )
                    )
                }
            }
        }
        if let detail = store.detail {
            let people = Array(uniqueCredits(in: detail).prefix(36))
            if !people.isEmpty {
                sections.append(
                    KeyboardSection(
                        id: Self.peopleSectionID,
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
            [section.id] + section.targets.map(String.init(describing:))
        }
    }

    private var selectedPersonID: String? {
        guard case let .person(id) = visibleKeyboardSelection else { return nil }
        return id
    }

    private var selectedMovieVariantID: String? {
        guard case let .movieVariant(id) = visibleKeyboardSelection else { return nil }
        return id
    }

    private var visibleKeyboardSelection: KeyboardTarget? {
        store.playbackOptions == nil && shortcuts.usesKeyboardNavigation
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
            level: .route,
            handoffToKeyboard: {
                guard let target = pointerSelection.wrappedValue,
                      sections.contains(where: { $0.targets.contains(target) }),
                      isNavigationTargetVisible(
                          target,
                          sections: sections,
                          visibleSectionIDs: visibleSectionIDs.wrappedValue,
                          visibleTargets: visibleTargets.wrappedValue
                      ) else {
                    return
                }
                selection.wrappedValue = target
                if let section = sections.first(where: { $0.targets.contains(target) }) {
                    rememberedSelections.wrappedValue[section.id] = target
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
                    rebasesOffscreenCandidate: shortcuts.inputModality == .pointer,
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
        rebasesOffscreenCandidate: Bool,
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
            rebasesOffscreenCandidate: rebasesOffscreenCandidate,
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
        rebasesOffscreenCandidate: Bool,
        visibleSectionIDs: Set<String>,
        visibleTargets: Set<KeyboardTarget>
    ) -> KeyboardTarget? {
        guard !visibleSectionIDs.isEmpty || !visibleTargets.isEmpty else { return candidate }
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
        return CineLarkNavigationOriginPolicy.resolve(
            candidate: candidate,
            isCandidateVisible: candidate.map {
                isNavigationTargetVisible(
                    $0,
                    sections: sections,
                    visibleSectionIDs: visibleSectionIDs,
                    visibleTargets: visibleTargets
                )
            } ?? false,
            rebasesOffscreenCandidate: rebasesOffscreenCandidate,
            orderedVisibleCandidates: orderedVisibleTargets,
            direction: direction
        )
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
        case let .episode(id):
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

    private func activateKeyboardSelection(
        _ target: KeyboardTarget?,
        selection: Binding<KeyboardTarget?>,
        rememberedSelections: Binding<[String: KeyboardTarget]>,
        scrollProxy: ScrollViewProxy
    ) -> Bool {
        guard let target else { return false }
        switch target {
        case .primaryPlayback:
            guard store.canPlayPrimary else { return false }
            store.send(.view(.playPrimary))
            return true
        case .favorite:
            guard !store.isUpdatingFavorite else { return false }
            store.send(.view(.toggleFavorite))
            return true
        case let .movieVariant(id):
            guard store.movieVariants.contains(where: { $0.id == id }) else { return false }
            store.send(.view(.movieVariantSelected(id)))
            return true
        case let .season(id):
            guard store.seasons.contains(where: { $0.id == id }) else { return false }
            store.send(.view(.seasonSelected(id)))
            return true
        case let .episode(id):
            guard let episode = visibleEpisodes.first(where: { $0.id == id }) else {
                return false
            }
            store.send(.view(.episodeSelected(episode)))
            return true
        case .showMore:
            let isExpanding = !showsAllEpisodes
            let destinationEpisode = isExpanding
                ? store.episodes.dropFirst(Self.collapsedEpisodeCount).first
                : store.episodes.prefix(Self.collapsedEpisodeCount).last
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
        case let .person(id):
            guard let detail = store.detail,
                  let person = uniqueCredits(in: detail).first(where: { $0.id == id }) else {
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
           !validTargets.contains(keyboardSelection) {
            self.keyboardSelection = nil
        }
        if let pointerSelection,
           !validTargets.contains(pointerSelection) {
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

    private func updatePointerSelection(_ target: KeyboardTarget, hovering: Bool) {
        if hovering {
            pointerSelection = target
        } else if pointerSelection == target {
            pointerSelection = nil
        }
    }

    private func uniqueCredits(in detail: MediaDetail) -> [PersonCredit] {
        var seen: Set<String> = []
        return (detail.directors + detail.cast).filter { seen.insert($0.id).inserted }
    }
}
