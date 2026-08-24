import SwiftUI
import CineLarkDomain

struct HomeView: View {
    private enum HeroCandidate: Hashable {
        case continueItem(String)
        case media(String)
    }

    private enum KeyboardTarget: Hashable {
        case heroPlayback(String)
        case heroDetails(String)
        case continueWatching(String)
        case media(sectionID: String, itemID: String)
        case collection(String)
    }

    private struct KeyboardSection {
        let id: String
        let targets: [KeyboardTarget]
    }

    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    @Bindable var model: AppModel
    @State private var highlightedContinueID: String?
    @State private var highlightedMediaID: String?
    @State private var pendingHero: HeroCandidate?
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
                        if !model.continueWatching.isEmpty {
                            ContinueWatchingShelf(
                                model: model,
                                selectedItemID: selectedContinueWatchingID,
                                isKeyboardNavigationActive: visibleKeyboardSelection != nil,
                                onPointerSelection: { item, hovering in
                                    updatePointerSelection(
                                        .continueWatching(item.id),
                                        hovering: hovering
                                    )
                                }
                            ) { item in
                                queueHero(.continueItem(item.id))
                            }
                            .id(Self.continueSectionID)
                        }

                        if model.isLoadingHome && model.hotItems.isEmpty {
                            ProgressView(language.localized("home.loading"))
                                .controlSize(.large)
                                .frame(maxWidth: .infinity, minHeight: 240)
                        }

                        if !model.hotItems.isEmpty {
                            PosterShelf(
                                title: language.localized("home.popular_now"),
                                items: model.hotItems,
                                selectedItemID: selectedMediaID(in: Self.hotSectionID),
                                isKeyboardNavigationActive: visibleKeyboardSelection != nil,
                                onPointerSelection: { item, hovering in
                                    updatePointerSelection(
                                        .media(
                                            sectionID: Self.hotSectionID,
                                            itemID: item.id
                                        ),
                                        hovering: hovering
                                    )
                                },
                                onHighlight: highlight
                            )
                            .id(Self.hotSectionID)
                        }

                        ForEach(model.collections) { collection in
                            let items = model.items(in: collection, sort: .newest)
                            if !items.isEmpty {
                                let sectionID = collectionSectionID(collection.id)
                                PosterShelf(
                                    title: collection.name,
                                    items: items,
                                    viewAllCollection: collection,
                                    selectedItemID: selectedMediaID(in: sectionID),
                                    isViewAllSelected: visibleKeyboardSelection == .collection(collection.id),
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
                                    onHighlight: highlight
                                )
                                .id(sectionID)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 64)
                }
                .scrollIndicators(.hidden)
                .onScrollTargetVisibilityChange(
                    idType: String.self,
                    threshold: 0.15
                ) { ids in
                    visibleShelfSectionIDs = ids
                }
                .onAppear {
                    registerKeyboardNavigation(scrollProxy: scrollProxy)
                }
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
                .task(id: pendingHero) {
                    guard let pendingHero else { return }
                    do {
                        try await Task.sleep(for: .milliseconds(120))
                    } catch {
                        return
                    }
                    switch pendingHero {
                    case .continueItem(let id):
                        highlightedContinueID = id
                        highlightedMediaID = nil
                    case .media(let id):
                        highlightedMediaID = id
                        highlightedContinueID = nil
                    }
                }
            }
            .zIndex(1)
        }
        .background(CineLarkPageBackground())
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle(language.localized("nav.home"))
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { height in
            viewportHeight = height
        }
    }

    private static let heroSectionID = "home.hero"
    private static let continueSectionID = "home.continue"
    private static let hotSectionID = "home.hot"

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            CineLarkCinematicBackdrop(
                url: featuredSummary?.backdropURL ?? featuredSummary?.posterURL,
                height: heroHeight,
                leadingShade: 0.88
            )
            .id(featuredSummary?.id)
            .transition(.opacity)

            VStack(alignment: .leading, spacing: 18) {
                if let featuredSummary {
                    Text(
                        language.localized(
                            featuredSummary.kind == .movie ? "detail.movie" : "detail.series"
                        )
                    )
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                    Text(featuredSummary.title)
                        .font(CineLarkDesign.Typography.heroTitle)
                        .lineLimit(2)
                        .frame(maxWidth: 720, alignment: .leading)

                    MediaFacts(
                        item: featuredSummary,
                        fields: .extended,
                        spacing: 12,
                        font: .callout.weight(.semibold)
                    )

                    if let synopsis = featuredSummary.synopsis, !synopsis.isEmpty {
                        Text(synopsis)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(3)
                            .frame(maxWidth: 680, alignment: .leading)
                    }

                    heroActions(for: featuredSummary)
                } else if model.isLoadingHome {
                    ProgressView(language.localized("home.loading"))
                        .controlSize(.large)
                } else {
                    Text("CineLark")
                        .font(CineLarkDesign.Typography.heroTitle)
                }
            }
            .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
            .padding(.bottom, heroContentBottomPadding)
            .animation(CineLarkDesign.Motion.hero, value: featuredSummary?.id)

        }
        .frame(height: heroHeight)
        .clipped()
    }

    private var heroHeight: CGFloat {
        min(690, max(440, viewportHeight * 0.82))
    }

    private var heroContentBottomPadding: CGFloat {
        model.continueWatching.isEmpty ? 64 : 170
    }

    private var contentOverlap: CGFloat {
        guard !model.continueWatching.isEmpty else { return 0 }
        return 118
    }

    @ViewBuilder
    private func heroActions(for item: MediaSummary) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if let featuredContinue {
                    Button {
                        Task { await model.play(featuredContinue) }
                    } label: {
                        Label(
                            language.localized(
                                "detail.continue",
                                language.progressPercent(featuredContinue.userState.progress)
                            ),
                            systemImage: "play.fill"
                        )
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                    .disabled(model.playingItemID != nil)
                    .cineLarkFocusSurface(
                        isActive: visibleKeyboardSelection == .heroPlayback(featuredContinue.id),
                        cornerRadius: 22,
                        scale: 1.02
                    )
                    .cineLarkPointerSelection { hovering in
                        updatePointerSelection(
                            .heroPlayback(featuredContinue.id),
                            hovering: hovering
                        )
                    }
                }

                if let featuredContinue {
                    NavigationLink(value: featuredContinue.mediaSummary) {
                        Label(language.localized("home.open_details"), systemImage: "info.circle")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.extraLarge)
                    .focusEffectDisabled()
                    .cineLarkFocusSurface(
                        isActive: visibleKeyboardSelection == .heroDetails(featuredContinue.mediaSummary.id),
                        cornerRadius: 22,
                        scale: 1.02
                    )
                    .cineLarkPointerSelection { hovering in
                        updatePointerSelection(
                            .heroDetails(featuredContinue.mediaSummary.id),
                            hovering: hovering
                        )
                    }
                } else {
                    NavigationLink(value: item) {
                        Label(language.localized("home.open_details"), systemImage: "info.circle")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                    .focusEffectDisabled()
                    .cineLarkFocusSurface(
                        isActive: visibleKeyboardSelection == .heroDetails(item.id),
                        cornerRadius: 22,
                        scale: 1.02
                    )
                    .cineLarkPointerSelection { hovering in
                        updatePointerSelection(
                            .heroDetails(item.id),
                            hovering: hovering
                        )
                    }
                }
            }
        }
    }

    private var featuredContinue: ContinueWatchingItem? {
        if let highlightedContinueID,
           let highlighted = model.continueWatching.first(where: { $0.id == highlightedContinueID }) {
            return highlighted
        }
        guard highlightedMediaID == nil else { return nil }
        return model.continueWatching.first
    }

    private var featuredSummary: MediaSummary? {
        if let featuredContinue {
            return knownItems.first(where: { $0.id == featuredContinue.mediaSummary.id })
                ?? featuredContinue.mediaSummary
        }
        if let highlightedMediaID,
           let highlighted = knownItems.first(where: { $0.id == highlightedMediaID }) {
            return highlighted
        }
        return model.hotItems.first
    }

    private var knownItems: [MediaSummary] {
        var seen: Set<String> = []
        let collectionItems = model.collections.flatMap {
            model.items(in: $0, sort: .newest)
        }
        return (model.hotItems + collectionItems).filter { seen.insert($0.id).inserted }
    }

    private func highlight(_ item: MediaSummary) {
        queueHero(.media(item.id))
    }

    private func queueHero(_ candidate: HeroCandidate) {
        pendingHero = candidate
    }

    private var keyboardSections: [KeyboardSection] {
        var sections: [KeyboardSection] = []
        if let featuredSummary {
            var targets: [KeyboardTarget] = []
            if let featuredContinue {
                targets.append(.heroPlayback(featuredContinue.id))
            }
            targets.append(.heroDetails(featuredSummary.id))
            sections.append(KeyboardSection(id: Self.heroSectionID, targets: targets))
        }
        if !model.continueWatching.isEmpty {
            sections.append(
                KeyboardSection(
                    id: Self.continueSectionID,
                    targets: model.continueWatching.map { .continueWatching($0.id) }
                )
            )
        }
        if !model.hotItems.isEmpty {
            sections.append(
                KeyboardSection(
                    id: Self.hotSectionID,
                    targets: model.hotItems.map {
                        .media(sectionID: Self.hotSectionID, itemID: $0.id)
                    }
                )
            )
        }
        for collection in model.collections {
            let items = model.items(in: collection, sort: .newest)
            guard !items.isEmpty else { continue }
            let sectionID = collectionSectionID(collection.id)
            let mediaTargets = items.map {
                KeyboardTarget.media(sectionID: sectionID, itemID: $0.id)
            }
            sections.append(
                KeyboardSection(
                    id: sectionID,
                    targets: mediaTargets + [.collection(collection.id)]
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

    private var selectedContinueWatchingID: String? {
        guard case .continueWatching(let id) = visibleKeyboardSelection else { return nil }
        return id
    }

    private func selectedMediaID(in sectionID: String) -> String? {
        guard case .media(let selectedSectionID, let itemID) = visibleKeyboardSelection,
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
                guard let pointerTarget = pointerSelection.wrappedValue,
                      sections.contains(where: {
                          $0.targets.contains(pointerTarget)
                      }),
                      isNavigationTargetVisible(
                          pointerTarget,
                          sections: sections,
                          visibleSectionIDs: visibleSectionIDs.wrappedValue
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
        let boundarySection = direction == .down
            ? visibleSections.last
            : visibleSections.first
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
              let targetSection = sections.first(where: {
                  $0.targets.contains(target)
              }) else {
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
        guard let scrollID else { return }
        scrollCorrectionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(240))
            } catch {
                return
            }
            scrollProxy.scrollTo(scrollID, anchor: .top)
        }
        switch target {
        case .continueWatching(let id), .heroPlayback(let id):
            queueHero(.continueItem(id))
        case .media(_, let itemID):
            queueHero(.media(itemID))
        case .heroDetails, .collection:
            break
        }
    }

    private func activateKeyboardSelection(_ target: KeyboardTarget?) -> Bool {
        guard let target else { return false }
        switch target {
        case .heroPlayback(let id), .continueWatching(let id):
            guard let item = model.continueWatching.first(where: { $0.id == id }),
                  model.playingItemID == nil else {
                return false
            }
            Task { await model.play(item) }
            return true
        case .heroDetails(let id):
            guard let item = featuredSummary?.id == id
                ? featuredSummary
                : knownItems.first(where: { $0.id == id }) else {
                return false
            }
            return shortcuts.openMedia(item)
        case .media(_, let id):
            guard let item = knownItems.first(where: { $0.id == id }) else { return false }
            return shortcuts.openMedia(item)
        case .collection(let id):
            guard let collection = model.collections.first(where: { $0.id == id }) else {
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
