import SwiftUI
import CineLarkDomain

struct FavoritesView: View {
    private enum Tab: CaseIterable, Identifiable {
        case series
        case movies
        case people

        var id: Self { self }

        var keyboardID: String {
            switch self {
            case .series: "favorites.series"
            case .movies: "favorites.movies"
            case .people: "favorites.people"
            }
        }

        func title(language: AppLanguage) -> String {
            switch self {
            case .series: language.localized("favorites.series")
            case .movies: language.localized("favorites.movies")
            case .people: language.localized("favorites.people")
            }
        }
    }

    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    @State private var model: FavoritesModel
    @State private var selectedTab: Tab = .series
    @State private var selectedPersonID: String?
    @State private var peopleKeyboardOwner = UUID()
    @State private var peopleGridWidth: CGFloat = 0
    @State private var keyboardSelectedTabID: String?
    @State private var rememberedTabID: String?
    @State private var rememberedPersonID: String?
    @State private var pointerSelectedTabID: String?
    @State private var pointerSelectedPersonID: String?

    init(provider: any MediaLibraryProvider) {
        _model = State(initialValue: FavoritesModel(provider: provider))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CineLarkPageHeader(language.localized("favorites.title"))
            favoriteSelector
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CineLarkPageBackground())
        .navigationTitle(language.localized("favorites.title"))
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
    }

    private var favoriteSelector: some View {
        CineLarkFilterBar(selectedID: keyboardSelectedTabID) {
            ForEach(Tab.allCases) { tab in
                CineLarkFilterButton(
                    title: tab.title(language: language),
                    count: count(for: tab),
                    isSelected: selectedTab == tab,
                    isKeyboardSelected: keyboardSelectedTabID == tab.keyboardID,
                    onPointerSelection: { hovering in
                        if hovering {
                            pointerSelectedTabID = tab.keyboardID
                        } else if pointerSelectedTabID == tab.keyboardID {
                            pointerSelectedTabID = nil
                        }
                    }
                ) {
                    selectedTab = tab
                }
                .id(tab.keyboardID)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.movies.isEmpty && model.series.isEmpty && model.people.isEmpty {
            ProgressView(language.localized("favorites.loading"))
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch selectedTab {
            case .series:
                mediaContent(model.series, emptyKey: "favorites.no_series")
            case .movies:
                mediaContent(model.movies, emptyKey: "favorites.no_movies")
            case .people:
                peopleContent
            }
        }
    }

    @ViewBuilder
    private func mediaContent(_ items: [MediaSummary], emptyKey: String) -> some View {
        ZStack {
            PosterGrid(
                items: items,
                topContentInset: CineLarkDesign.Layout.focusSafeTopInset,
                pointerSelectedLeadingActionID: pointerSelectedTabID,
                preferredLeadingKeyboardID: selectedTab.keyboardID,
                leadingKeyboardActions: favoriteTabKeyboardActions,
                onLeadingSelectionChange: { keyboardSelectedTabID = $0 }
            )

            if items.isEmpty {
                ContentUnavailableView(
                    language.localized(emptyKey),
                    systemImage: "heart",
                    description: Text(language.localized("favorites.no_media_description"))
                )
            }
        }
    }

    private var peopleContent: some View {
        ScrollViewReader { scrollProxy in
            ZStack {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(
                                    minimum: CineLarkDesign.Media.posterWidth,
                                    maximum: CineLarkDesign.Media.posterWidth + 26
                                ),
                                spacing: CineLarkDesign.Layout.posterGridColumnSpacing,
                                alignment: .top
                            )
                        ],
                        spacing: CineLarkDesign.Layout.posterGridRowSpacing
                    ) {
                        ForEach(model.people) { person in
                            FavoritePersonLink(
                                person: person,
                                credit: credit(for: person),
                                isKeyboardSelected: selectedPersonID == person.id,
                                isKeyboardNavigationActive: selectedPersonID != nil ||
                                    keyboardSelectedTabID != nil,
                                onPointerSelection: { hovering in
                                    if hovering {
                                        pointerSelectedPersonID = person.id
                                    } else if pointerSelectedPersonID == person.id {
                                        pointerSelectedPersonID = nil
                                    }
                                }
                            )
                            .id(person.id)
                        }
                    }
                    .focusSection()
                    .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
                    .padding(.top, CineLarkDesign.Layout.focusSafeTopInset)
                    .padding(.bottom, 34)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    peopleGridWidth = width
                    registerPeopleNavigation(scrollProxy: scrollProxy)
                }
                .onAppear {
                    registerPeopleNavigation(scrollProxy: scrollProxy)
                }
                .onDisappear {
                    shortcuts.removeNavigationSurface(owner: peopleKeyboardOwner)
                    pointerSelectedPersonID = nil
                }
                .onChange(of: model.people.map(\.id)) {
                    if let selectedPersonID,
                       !model.people.contains(where: { $0.id == selectedPersonID }) {
                        self.selectedPersonID = nil
                    }
                    if let pointerSelectedPersonID,
                       !model.people.contains(where: { $0.id == pointerSelectedPersonID }) {
                        self.pointerSelectedPersonID = nil
                    }
                    if let rememberedPersonID,
                       !model.people.contains(where: { $0.id == rememberedPersonID }) {
                        self.rememberedPersonID = nil
                    }
                    registerPeopleNavigation(scrollProxy: scrollProxy)
                }

                if model.people.isEmpty {
                    ContentUnavailableView(
                        language.localized("favorites.no_people"),
                        systemImage: "person.crop.circle",
                        description: Text(language.localized("favorites.no_people_description"))
                    )
                }
            }
        }
    }

    private func count(for tab: Tab) -> Int {
        switch tab {
        case .series: model.seriesCount
        case .movies: model.movieCount
        case .people: model.peopleCount
        }
    }

    private func credit(for person: PersonDetail) -> PersonCredit {
        PersonCredit(
            id: person.id,
            name: person.name,
            character: nil,
            avatarURL: person.avatarURL,
            order: nil
        )
    }

    private var peopleColumnsPerRow: Int {
        let contentWidth = max(
            0,
            peopleGridWidth - (CineLarkDesign.Layout.contentMargin * 2)
        )
        let itemWidth = CineLarkDesign.Media.posterWidth +
            CineLarkDesign.Layout.posterGridColumnSpacing
        return max(
            1,
            Int(
                (contentWidth + CineLarkDesign.Layout.posterGridColumnSpacing) /
                    itemWidth
            )
        )
    }

    private func registerPeopleNavigation(scrollProxy: ScrollViewProxy) {
        let personIDs = model.people.map(\.id)
        let tabs = Tab.allCases
        let columnCount = peopleColumnsPerRow
        let selection = $selectedPersonID
        let tabSelection = $keyboardSelectedTabID
        let rememberedPerson = $rememberedPersonID
        let rememberedTab = $rememberedTabID
        let pointerPersonSelection = $pointerSelectedPersonID
        let pointerTabSelection = $pointerSelectedTabID
        shortcuts.setNavigationSurface(
            owner: peopleKeyboardOwner,
            handoffToKeyboard: {
                if let pointerPersonID = pointerPersonSelection.wrappedValue,
                   personIDs.contains(pointerPersonID) {
                    selection.wrappedValue = pointerPersonID
                    rememberedPerson.wrappedValue = pointerPersonID
                    tabSelection.wrappedValue = nil
                } else if let pointerTabID = pointerTabSelection.wrappedValue,
                          tabs.contains(where: {
                              $0.keyboardID == pointerTabID
                          }) {
                    selection.wrappedValue = nil
                    tabSelection.wrappedValue = pointerTabID
                    rememberedTab.wrappedValue = pointerTabID
                }
            },
            move: { direction in
                let handedPointerPersonID = shortcuts.inputModality == .pointer
                    ? pointerPersonSelection.wrappedValue
                    : nil
                let handedPointerTabID = shortcuts.inputModality == .pointer &&
                    handedPointerPersonID == nil
                    ? pointerTabSelection.wrappedValue
                    : nil
                if let selectedTabID = handedPointerTabID ?? tabSelection.wrappedValue,
                   let selectedTabIndex = tabs.firstIndex(where: {
                       $0.keyboardID == selectedTabID
                   }) {
                    if direction == .left || direction == .right {
                        let delta = direction == .left ? -1 : 1
                        let targetIndex = min(
                            max(0, selectedTabIndex + delta),
                            tabs.count - 1
                        )
                        tabSelection.wrappedValue = tabs[targetIndex].keyboardID
                        rememberedTab.wrappedValue = tabs[targetIndex].keyboardID
                        return true
                    }
                    guard direction == .down,
                          let targetPersonID = rememberedPerson.wrappedValue.flatMap({
                              personIDs.contains($0) ? $0 : nil
                          }) ?? personIDs.first else {
                        return true
                    }
                    tabSelection.wrappedValue = nil
                    selectPerson(
                        targetPersonID,
                        selection: selection,
                        rememberedSelection: rememberedPerson,
                        scrollProxy: scrollProxy
                    )
                    return true
                }
                guard !personIDs.isEmpty else {
                    let fallbackTabID = tabs.contains(where: {
                        $0.keyboardID == rememberedTab.wrappedValue
                    }) ? rememberedTab.wrappedValue : selectedTab.keyboardID
                    tabSelection.wrappedValue = fallbackTabID
                    rememberedTab.wrappedValue = fallbackTabID
                    return true
                }
                guard let selectedID = handedPointerPersonID ?? selection.wrappedValue,
                      let currentIndex = personIDs.firstIndex(of: selectedID) else {
                    let fallbackTabID = tabs.contains(where: {
                        $0.keyboardID == rememberedTab.wrappedValue
                    }) ? rememberedTab.wrappedValue : selectedTab.keyboardID
                    tabSelection.wrappedValue = fallbackTabID
                    rememberedTab.wrappedValue = fallbackTabID
                    return true
                }
                let targetIndex: Int
                switch direction {
                case .left:
                    targetIndex = max(0, currentIndex - 1)
                case .right:
                    targetIndex = min(personIDs.count - 1, currentIndex + 1)
                case .up:
                    if currentIndex < columnCount {
                        selection.wrappedValue = nil
                        let fallbackTabID = tabs.contains(where: {
                            $0.keyboardID == rememberedTab.wrappedValue
                        }) ? rememberedTab.wrappedValue : selectedTab.keyboardID
                        tabSelection.wrappedValue = fallbackTabID
                        rememberedTab.wrappedValue = fallbackTabID
                        return true
                    }
                    targetIndex = max(0, currentIndex - columnCount)
                case .down:
                    targetIndex = min(personIDs.count - 1, currentIndex + columnCount)
                }
                selectPerson(
                    personIDs[targetIndex],
                    selection: selection,
                    rememberedSelection: rememberedPerson,
                    scrollProxy: scrollProxy
                )
                return true
            },
            activate: {
                let handedPointerPersonID = shortcuts.inputModality == .pointer
                    ? pointerPersonSelection.wrappedValue
                    : nil
                let handedPointerTabID = shortcuts.inputModality == .pointer &&
                    handedPointerPersonID == nil
                    ? pointerTabSelection.wrappedValue
                    : nil
                if let selectedTabID = handedPointerTabID ?? tabSelection.wrappedValue,
                   let tab = tabs.first(where: { $0.keyboardID == selectedTabID }) {
                    selectedTab = tab
                    return true
                }
                guard let selectedID = handedPointerPersonID ?? selection.wrappedValue,
                      let person = model.people.first(where: { $0.id == selectedID }) else {
                    return false
                }
                return shortcuts.openPerson(credit(for: person))
            }
        )
    }

    private func selectPerson(
        _ personID: String,
        selection: Binding<String?>,
        rememberedSelection: Binding<String?>,
        scrollProxy: ScrollViewProxy
    ) {
        withAnimation(.easeOut(duration: 0.2)) {
            keyboardSelectedTabID = nil
            selection.wrappedValue = personID
            rememberedSelection.wrappedValue = personID
            scrollProxy.scrollTo(personID, anchor: .top)
        }
    }

    private var favoriteTabKeyboardActions: [PosterGridLeadingKeyboardAction] {
        Tab.allCases.map { tab in
            PosterGridLeadingKeyboardAction(id: tab.keyboardID) {
                selectedTab = tab
                return true
            }
        }
    }
}

private struct FavoritePersonLink: View {
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let person: PersonDetail
    let credit: PersonCredit
    let isKeyboardSelected: Bool
    let isKeyboardNavigationActive: Bool
    let onPointerSelection: (Bool) -> Void
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(value: credit) {
            VStack(spacing: 12) {
                ArtworkView(url: person.avatarURL)
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular, in: Circle())
                    }
                    .cineLarkFocusSurface(
                        isActive: isActive,
                        cornerRadius: 75,
                        scale: 1.05
                    )
                    .cineLarkKeyboardSelectionHint(isActive: isKeyboardSelected)
                Text(person.name)
                    .font(CineLarkDesign.Typography.cardTitle)
                    .lineLimit(1)
            }
            .frame(width: CineLarkDesign.Media.posterWidth)
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
