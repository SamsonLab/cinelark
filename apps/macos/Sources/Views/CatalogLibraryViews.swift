import ComposableArchitecture
import SwiftUI
import CineLarkDomain
import CineLarkProfile

struct CatalogHomeView: View {
    private enum KeyboardTarget: Hashable {
        case heroPlayback(String)
        case heroDetails(String)
        case continueWatching(ProfileMediaKey)
        case media(sectionID: String, itemID: String)
        case collection(String)
    }

    private struct KeyboardSection {
        let id: String
        let targets: [KeyboardTarget]
    }

    @Environment(\.appLanguage) private var language
    @Environment(\.activeMediaSourceID) private var activeSourceID
    @Environment(\.activeProfileID) private var activeProfileID
    @Environment(ShortcutCoordinator.self) private var shortcuts
    @Bindable var store: StoreOf<LibraryFeature>
    @State private var highlightedItemID: String?
    @State private var viewportHeight: CGFloat = 900
    @State private var keyboardSelection: KeyboardTarget?
    @State private var rememberedKeyboardSelections: [String: KeyboardTarget] = [:]
    @State private var pointerSelection: KeyboardTarget?
    @State private var visibleShelfSectionIDs: [String] = []
    @State private var keyboardOwner = UUID()
    @State private var scrollCorrectionTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: -contentOverlap) {
            hero
                .zIndex(0)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 44) {
                        if !store.resumeItems.isEmpty {
                            CatalogContinueWatchingShelf(
                                items: store.resumeItems,
                                store: store,
                                selectedItemID: selectedContinueWatchingID,
                                isKeyboardNavigationActive: visibleKeyboardSelection != nil,
                                onPointerSelection: { item, hovering in
                                    updatePointerSelection(
                                        .continueWatching(item.id),
                                        hovering: hovering
                                    )
                                },
                                onHighlight: { highlightedItemID = $0.summary.id }
                            )
                            .id(Self.continueSectionID)
                        }

                        if store.isLoadingOverview,
                           store.latestItems.isEmpty,
                           store.resumeItems.isEmpty {
                            ProgressView(language.localized("home.loading"))
                                .controlSize(.large)
                                .frame(maxWidth: .infinity, minHeight: 240)
                        }

                        if !store.latestItems.isEmpty {
                            PosterShelf(
                                title: language.localized("home.popular_now"),
                                items: store.latestItems.map(\.summary),
                                selectedItemID: selectedMediaID(in: Self.latestSectionID),
                                isKeyboardNavigationActive: visibleKeyboardSelection != nil,
                                onPointerSelection: { item, hovering in
                                    updatePointerSelection(
                                        .media(
                                            sectionID: Self.latestSectionID,
                                            itemID: item.id
                                        ),
                                        hovering: hovering
                                    )
                                },
                                onHighlight: { highlightedItemID = $0.id }
                            )
                            .id(Self.latestSectionID)
                        }

                        ForEach(store.collections.prefix(8)) { collection in
                            let items = items(in: collection)
                            if !items.isEmpty {
                                let sectionID = collectionSectionID(collection.id)
                                PosterShelf(
                                    title: collection.name,
                                    items: items.map(\.summary),
                                    viewAllCollection: collection,
                                    selectedItemID: selectedMediaID(in: sectionID),
                                    isViewAllSelected: visibleKeyboardSelection ==
                                        .collection(collection.id),
                                    isKeyboardNavigationActive: visibleKeyboardSelection != nil,
                                    onPointerSelection: { item, hovering in
                                        updatePointerSelection(
                                            .media(sectionID: sectionID, itemID: item.id),
                                            hovering: hovering
                                        )
                                    },
                                    onViewAllPointerSelection: { collection, hovering in
                                        updatePointerSelection(
                                            .collection(collection.id),
                                            hovering: hovering
                                        )
                                    },
                                    onHighlight: { highlightedItemID = $0.id }
                                )
                                .id(sectionID)
                            }
                        }

                        if !store.isLoadingOverview,
                           store.latestItems.isEmpty,
                           store.resumeItems.isEmpty,
                           store.collections.isEmpty {
                            ContentUnavailableView(
                                language.localized("collection.empty"),
                                systemImage: "rectangle.stack.badge.plus",
                                description: Text(language.localized("home.collection_help"))
                            )
                            .frame(maxWidth: .infinity, minHeight: 320)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 64)
                }
                .scrollIndicators(.hidden)
                .onScrollTargetVisibilityChange(
                    idType: String.self,
                    threshold: 0.15
                ) { visibleShelfSectionIDs = $0 }
                .onAppear { registerKeyboardNavigation(scrollProxy: scrollProxy) }
                .onDisappear {
                    scrollCorrectionTask?.cancel()
                    pointerSelection = nil
                    visibleShelfSectionIDs = []
                    shortcuts.removeNavigationSurface(owner: keyboardOwner)
                }
                .onChange(of: keyboardSignature) {
                    reconcileKeyboardSelection()
                    registerKeyboardNavigation(scrollProxy: scrollProxy)
                }
            }
            .zIndex(1)
        }
        .background(CineLarkPageBackground())
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle(language.localized("nav.home"))
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { viewportHeight = $0 }
        .task { store.send(.view(.loadOverview)) }
    }

    private static let heroSectionID = "home.hero"
    private static let continueSectionID = "home.continue"
    private static let latestSectionID = "home.latest"

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            CineLarkCinematicBackdrop(
                url: featuredItem?.backdropURL ?? featuredItem?.posterURL,
                height: heroHeight,
                leadingShade: 0.88
            )
            .id(featuredItem?.id)
            .transition(.opacity)

            VStack(alignment: .leading, spacing: 18) {
                if let featuredItem {
                    Text(language.localized(
                        featuredItem.kind == .movie ? "detail.movie" : "detail.series"
                    ))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                    Text(featuredItem.title)
                        .font(CineLarkDesign.Typography.heroTitle)
                        .lineLimit(2)
                        .frame(maxWidth: 720, alignment: .leading)

                    MediaFacts(
                        item: featuredItem,
                        fields: .extended,
                        spacing: 12,
                        font: .callout.weight(.semibold)
                    )

                    if let synopsis = featuredItem.synopsis, !synopsis.isEmpty {
                        Text(synopsis)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(3)
                            .frame(maxWidth: 680, alignment: .leading)
                    }

                    heroActions(for: featuredItem)
                } else if store.isLoadingOverview {
                    ProgressView(language.localized("home.loading"))
                        .controlSize(.large)
                } else {
                    Text("CineLark")
                        .font(CineLarkDesign.Typography.heroTitle)
                }
            }
            .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
            .padding(.bottom, store.resumeItems.isEmpty ? 64 : 170)
            .animation(CineLarkDesign.Motion.hero, value: featuredItem?.id)
        }
        .frame(height: heroHeight)
        .clipped()
    }

    @ViewBuilder
    private func heroActions(for item: MediaSummary) -> some View {
        HStack(spacing: 12) {
            if let resume = store.resumeItems.first(where: { $0.summary.id == item.id }) {
                Button {
                    store.send(.view(.playResume(resume)))
                } label: {
                    Label(
                        language.localized(
                            "detail.continue",
                            language.progressPercent(item.userState.progress)
                        ),
                        systemImage: "play.fill"
                    )
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .focusEffectDisabled()
                .cineLarkFocusSurface(
                    isActive: visibleKeyboardSelection == .heroPlayback(item.id),
                    cornerRadius: 22,
                    scale: 1.02
                )
                .cineLarkPointerSelection { hovering in
                    updatePointerSelection(.heroPlayback(item.id), hovering: hovering)
                }
            } else if let snapshot = featuredSnapshot,
                      snapshot.summary.kind == .movie {
                Button {
                    store.send(.view(.play(snapshot)))
                } label: {
                    Label(language.localized("detail.play"), systemImage: "play.fill")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .focusEffectDisabled()
                .cineLarkFocusSurface(
                    isActive: visibleKeyboardSelection == .heroPlayback(item.id),
                    cornerRadius: 22,
                    scale: 1.02
                )
                .cineLarkPointerSelection { hovering in
                    updatePointerSelection(.heroPlayback(item.id), hovering: hovering)
                }
            }

            if item.kind != .episode {
                NavigationLink(
                    state: NavigationFeature.Path.State.media(
                        MediaRouteFeature.State(
                            item: item,
                            transitionID: UUID(),
                            sourceID: activeSourceID,
                            profileID: activeProfileID
                        )
                    )
                ) {
                    Label(language.localized("home.open_details"), systemImage: "info.circle")
                }
                .buttonStyle(.glass)
                .controlSize(.extraLarge)
                .focusEffectDisabled()
                .cineLarkFocusSurface(
                    isActive: visibleKeyboardSelection == .heroDetails(item.id),
                    cornerRadius: 22,
                    scale: 1.02
                )
                .cineLarkPointerSelection { hovering in
                    updatePointerSelection(.heroDetails(item.id), hovering: hovering)
                }
            }
        }
    }

    private var featuredItem: MediaSummary? {
        if let highlightedItemID {
            if let resume = store.resumeItems.first(where: { $0.summary.id == highlightedItemID }) {
                return resume.summary
            }
            if let item = allShelfItems.first(where: { $0.summary.id == highlightedItemID }) {
                return item.summary
            }
        }
        return store.resumeItems.first?.summary ?? store.latestItems.first?.summary
    }

    private var featuredSnapshot: LibraryFeature.ItemSnapshot? {
        guard let featuredItem else { return nil }
        return allShelfItems.first { $0.summary.id == featuredItem.id }
    }

    private var allShelfItems: [LibraryFeature.ItemSnapshot] {
        store.latestItems + store.collections.flatMap { items(in: $0) }
    }

    private func items(in collection: MediaCollection) -> [LibraryFeature.ItemSnapshot] {
        store.collectionItemIDs[collection.id, default: []].compactMap {
            store.snapshots[$0]
        }
    }

    private var heroHeight: CGFloat {
        min(690, max(440, viewportHeight * 0.82))
    }

    private var contentOverlap: CGFloat {
        store.resumeItems.isEmpty ? 0 : 118
    }

    private var keyboardSections: [KeyboardSection] {
        var sections: [KeyboardSection] = []
        if let featuredItem {
            var targets: [KeyboardTarget] = []
            if store.resumeItems.contains(where: { $0.summary.id == featuredItem.id }) ||
                featuredSnapshot?.summary.kind == .movie {
                targets.append(.heroPlayback(featuredItem.id))
            }
            if featuredItem.kind != .episode {
                targets.append(.heroDetails(featuredItem.id))
            }
            if !targets.isEmpty {
                sections.append(KeyboardSection(id: Self.heroSectionID, targets: targets))
            }
        }
        if !store.resumeItems.isEmpty {
            sections.append(
                KeyboardSection(
                    id: Self.continueSectionID,
                    targets: store.resumeItems.map { .continueWatching($0.id) }
                )
            )
        }
        if !store.latestItems.isEmpty {
            sections.append(
                KeyboardSection(
                    id: Self.latestSectionID,
                    targets: store.latestItems.map {
                        .media(sectionID: Self.latestSectionID, itemID: $0.summary.id)
                    }
                )
            )
        }
        for collection in store.collections.prefix(8) {
            let collectionItems = items(in: collection)
            guard !collectionItems.isEmpty else { continue }
            let sectionID = collectionSectionID(collection.id)
            sections.append(
                KeyboardSection(
                    id: sectionID,
                    targets: collectionItems.map {
                        .media(sectionID: sectionID, itemID: $0.summary.id)
                    } + [.collection(collection.id)]
                )
            )
        }
        return sections
    }

    private var keyboardSignature: [String] {
        keyboardSections.flatMap { section in
            [section.id] + section.targets.map(String.init(describing:))
        }
    }

    private var selectedContinueWatchingID: ProfileMediaKey? {
        guard case let .continueWatching(id) = visibleKeyboardSelection else { return nil }
        return id
    }

    private func selectedMediaID(in sectionID: String) -> String? {
        guard case let .media(selectedSectionID, itemID) = visibleKeyboardSelection,
              selectedSectionID == sectionID else {
            return nil
        }
        return itemID
    }

    private var visibleKeyboardSelection: KeyboardTarget? {
        shortcuts.usesKeyboardNavigation ? keyboardSelection : nil
    }

    private func collectionSectionID(_ collectionID: String) -> String {
        "home.collection.\(collectionID)"
    }

    private func registerKeyboardNavigation(scrollProxy: ScrollViewProxy) {
        let sections = keyboardSections
        let selection = $keyboardSelection
        let rememberedSelections = $rememberedKeyboardSelections
        let pointerSelection = $pointerSelection
        let visibleSectionIDs = $visibleShelfSectionIDs
        shortcuts.setNavigationSurface(
            owner: keyboardOwner,
            handoffToKeyboard: {
                guard let target = pointerSelection.wrappedValue,
                      sections.contains(where: { $0.targets.contains(target) }),
                      isNavigationTargetVisible(
                          target,
                          sections: sections,
                          visibleSectionIDs: visibleSectionIDs.wrappedValue
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
                    visibleSectionIDs: visibleSectionIDs.wrappedValue,
                    scrollProxy: scrollProxy
                )
            },
            activate: {
                activateKeyboardSelection(
                    shortcuts.inputModality == .pointer
                        ? pointerSelection.wrappedValue ?? selection.wrappedValue
                        : selection.wrappedValue
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
        visibleSectionIDs: [String],
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
            visibleSectionIDs: visibleSectionIDs
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

        let targetSectionIndex: Int
        let targetIndexInSection: Int?
        switch direction {
        case .left:
            targetSectionIndex = sectionIndex
            targetIndexInSection = max(0, targetIndex - 1)
        case .right:
            targetSectionIndex = sectionIndex
            targetIndexInSection = min(
                sections[sectionIndex].targets.count - 1,
                targetIndex + 1
            )
        case .up:
            targetSectionIndex = max(0, sectionIndex - 1)
            targetIndexInSection = targetSectionIndex == sectionIndex ? targetIndex : nil
        case .down:
            targetSectionIndex = min(sections.count - 1, sectionIndex + 1)
            targetIndexInSection = targetSectionIndex == sectionIndex ? targetIndex : nil
        }

        let targetSection = sections[targetSectionIndex]
        let target: KeyboardTarget
        if let targetIndexInSection {
            target = targetSection.targets[targetIndexInSection]
        } else if let rememberedTarget = rememberedSelections.wrappedValue[targetSection.id],
                  targetSection.targets.contains(rememberedTarget) {
            target = rememberedTarget
        } else if let firstTarget = targetSection.targets.first {
            target = firstTarget
        } else {
            return false
        }
        selectKeyboardTarget(
            target,
            sectionID: targetSection.id,
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
        visibleSectionIDs: [String]
    ) -> KeyboardTarget? {
        guard !visibleSectionIDs.isEmpty else { return candidate }
        if let candidate,
           isNavigationTargetVisible(
               candidate,
               sections: sections,
               visibleSectionIDs: visibleSectionIDs
           ) {
            return candidate
        }
        let visibleSections = sections.filter {
            $0.id != Self.heroSectionID && visibleSectionIDs.contains($0.id)
        }
        let boundarySection = direction == .down ? visibleSections.last : visibleSections.first
        guard let boundarySection else { return candidate }
        if let rememberedTarget = rememberedSelections[boundarySection.id],
           boundarySection.targets.contains(rememberedTarget) {
            return rememberedTarget
        }
        return boundarySection.targets.first
    }

    private func isNavigationTargetVisible(
        _ target: KeyboardTarget,
        sections: [KeyboardSection],
        visibleSectionIDs: [String]
    ) -> Bool {
        guard !visibleSectionIDs.isEmpty,
              let targetSection = sections.first(where: { $0.targets.contains(target) }) else {
            return true
        }
        if targetSection.id == Self.heroSectionID {
            return sections.first(where: { $0.id != Self.heroSectionID }).map {
                visibleSectionIDs.contains($0.id)
            } ?? true
        }
        return visibleSectionIDs.contains(targetSection.id)
    }

    private func selectKeyboardTarget(
        _ target: KeyboardTarget,
        sectionID: String,
        selection: Binding<KeyboardTarget?>,
        rememberedSelections: Binding<[String: KeyboardTarget]>,
        scrollProxy: ScrollViewProxy
    ) {
        let scrollID = sectionID == Self.heroSectionID
            ? keyboardSections.first(where: { $0.id != Self.heroSectionID })?.id
            : sectionID
        scrollCorrectionTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            selection.wrappedValue = target
            rememberedSelections.wrappedValue[sectionID] = target
            if let scrollID {
                scrollProxy.scrollTo(scrollID, anchor: .top)
            }
        }
        if let scrollID {
            scrollCorrectionTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(240))
                } catch {
                    return
                }
                scrollProxy.scrollTo(scrollID, anchor: .top)
            }
        }
        switch target {
        case let .continueWatching(id):
            highlightedItemID = store.resumeItems.first(where: { $0.id == id })?.summary.id
        case let .heroPlayback(id), let .media(_, id):
            highlightedItemID = id
        case .heroDetails, .collection:
            break
        }
    }

    private func activateKeyboardSelection(_ target: KeyboardTarget?) -> Bool {
        guard let target else { return false }
        switch target {
        case let .heroPlayback(id):
            if let resume = store.resumeItems.first(where: { $0.summary.id == id }) {
                store.send(.view(.playResume(resume)))
                return true
            }
            guard let snapshot = allShelfItems.first(where: {
                $0.summary.id == id && $0.summary.kind == .movie
            }) else {
                return false
            }
            store.send(.view(.play(snapshot)))
            return true
        case let .continueWatching(id):
            guard let item = store.resumeItems.first(where: { $0.id == id }) else {
                return false
            }
            store.send(.view(.playResume(item)))
            return true
        case let .heroDetails(id), let .media(_, id):
            guard let item = (featuredItem?.id == id ? featuredItem : nil) ??
                allShelfItems.first(where: { $0.summary.id == id })?.summary else {
                return false
            }
            return shortcuts.openMedia(item)
        case let .collection(id):
            guard let collection = store.collections.first(where: { $0.id == id }) else {
                return false
            }
            return shortcuts.openCollection(collection)
        }
    }

    private func reconcileKeyboardSelection() {
        let sectionsByID = Dictionary(
            uniqueKeysWithValues: keyboardSections.map { ($0.id, $0.targets) }
        )
        rememberedKeyboardSelections = rememberedKeyboardSelections.filter {
            sectionsByID[$0.key]?.contains($0.value) == true
        }
        if let keyboardSelection,
           !keyboardSections.contains(where: { $0.targets.contains(keyboardSelection) }) {
            self.keyboardSelection = nil
        }
        if let pointerSelection,
           !keyboardSections.contains(where: { $0.targets.contains(pointerSelection) }) {
            self.pointerSelection = nil
        }
    }

    private func updatePointerSelection(_ target: KeyboardTarget, hovering: Bool) {
        if hovering {
            pointerSelection = target
        } else if pointerSelection == target {
            pointerSelection = nil
        }
    }
}
