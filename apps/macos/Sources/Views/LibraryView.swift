import SwiftUI
import ComposableArchitecture
import CineLarkDomain

struct LibraryView: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    @Bindable var store: StoreOf<NavigationFeature>
    @Bindable var libraryStore: StoreOf<LibraryFeature>
    @Bindable var searchStore: StoreOf<SearchFeature>
    @Bindable var insightsStore: StoreOf<InsightsFeature>
    @Bindable var profileStore: StoreOf<ProfileFeature>
    @State private var actualColumnVisibility: NavigationSplitViewVisibility
    @Namespace private var mediaTransitionNamespace

    init(
        store: StoreOf<NavigationFeature>,
        libraryStore: StoreOf<LibraryFeature>,
        searchStore: StoreOf<SearchFeature>,
        insightsStore: StoreOf<InsightsFeature>,
        profileStore: StoreOf<ProfileFeature>
    ) {
        self.store = store
        self.libraryStore = libraryStore
        self.searchStore = searchStore
        self.insightsStore = insightsStore
        self.profileStore = profileStore
        _actualColumnVisibility = State(
            initialValue: store.sidebarVisible ? .all : .detailOnly
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $actualColumnVisibility) {
            VStack(spacing: 0) {
                List(selection: selection) {
                    Section {
                        navigationLink(.home, titleKey: "nav.home", symbol: "house", shortcut: 1)
                        navigationLink(.movies, titleKey: "nav.movies", symbol: "film.stack", shortcut: 2)
                        navigationLink(.series, titleKey: "nav.series", symbol: "tv", shortcut: 3)
                        navigationLink(.favorites, titleKey: "nav.favorites", symbol: "heart", shortcut: 4)
                        navigationLink(.search, titleKey: "nav.search", symbol: "magnifyingglass", shortcut: 5)
                        navigationLink(.insights, titleKey: "nav.insights", symbol: "chart.bar.xaxis", shortcut: 6)
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("CineLark")
            .navigationSplitViewColumnWidth(min: 190, ideal: 228, max: 280)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                destination
            } destination: { store in
                switch store.case {
                case .media(let routeStore):
                    if let detailStore = routeStore.scope(state: \.detail, action: \.detail) {
                        CatalogMediaDetailView(store: detailStore)
                    } else {
                        ContentUnavailableView(
                            "Media source unavailable",
                            systemImage: "externaldrive.badge.exclamationmark"
                        )
                    }

                case .collection(let routeStore):
                    CatalogCollectionView(
                        collection: routeStore.collection,
                        store: libraryStore
                    )

                case .person(let routeStore):
                    if let detailStore = routeStore.scope(state: \.detail, action: \.detail) {
                        CatalogPersonDetailView(store: detailStore)
                    } else {
                        ContentUnavailableView(
                            "Media source unavailable",
                            systemImage: "externaldrive.badge.exclamationmark"
                        )
                    }
                }
            }
            .environment(\.mediaTransitionNamespace, mediaTransitionNamespace)
            .background(CineLarkPageBackground())
        }
        .navigationSplitViewStyle(.prominentDetail)
        .environment(\.activeMediaSourceID, profileStore.activeSourceID)
        .environment(\.activeProfileID, profileStore.activeProfileID)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    let isVisible = !store.sidebarVisible
                    store.send(.view(.sidebarVisibilityChanged(isVisible)))
                    actualColumnVisibility = isVisible ? .all : .detailOnly
                } label: {
                    Label("Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if store.selection == .insights {
                        insightsStore.send(.view(.reload))
                    } else {
                        libraryStore.send(.view(.reload))
                    }
                } label: {
                    Label(
                        language.localized("general.refresh"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .help(language.localized("general.refresh"))
                .disabled(
                    store.selection == .insights
                        ? insightsStore.isLoading
                        : libraryStore.isLoadingOverview || libraryStore.isRefreshing
                )
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .windowToolbarFullScreenVisibility(.onHover)
        .task {
            shortcuts.setBackAction {
                guard !store.path.isEmpty else { return false }
                store.send(.view(.backRequested))
                return true
            }
            shortcuts.setOpenMediaAction { item in
                store.send(
                    .view(.mediaRequested(item, transitionID: UUID()))
                )
                return true
            }
            shortcuts.setOpenCollectionAction { collection in
                store.send(.view(.collectionRequested(collection)))
                return true
            }
            shortcuts.setOpenPersonAction { person in
                store.send(.view(.personRequested(person)))
                return true
            }
            shortcuts.setFixedAction(.navigation(1)) {
                store.send(.view(.sectionSelected(.home)))
                return true
            }
            shortcuts.setFixedAction(.navigation(2)) {
                store.send(.view(.sectionSelected(.movies)))
                return true
            }
            shortcuts.setFixedAction(.navigation(3)) {
                store.send(.view(.sectionSelected(.series)))
                return true
            }
            shortcuts.setFixedAction(.navigation(4)) {
                store.send(.view(.sectionSelected(.favorites)))
                return true
            }
            shortcuts.setFixedAction(.navigation(5)) {
                store.send(.view(.sectionSelected(.search)))
                return true
            }
            shortcuts.setFixedAction(.navigation(6)) {
                store.send(.view(.sectionSelected(.insights)))
                return true
            }
            shortcuts.setSectionAction(.home) {
                store.send(.view(.sectionSelected(.home)))
                return true
            }
            shortcuts.setSectionAction(.movies) {
                store.send(.view(.sectionSelected(.movies)))
                return true
            }
            shortcuts.setSectionAction(.series) {
                store.send(.view(.sectionSelected(.series)))
                return true
            }
            shortcuts.setSectionAction(.favorites) {
                store.send(.view(.sectionSelected(.favorites)))
                return true
            }
            shortcuts.setSectionAction(.search) {
                store.send(.view(.sectionSelected(.search)))
                return true
            }
            shortcuts.setSectionAction(.insights) {
                store.send(.view(.sectionSelected(.insights)))
                return true
            }
            shortcuts.setFixedAction(.refresh) {
                libraryStore.send(.view(.reload))
                return true
            }
        }
        .onDisappear {
            shortcuts.setBackAction(nil)
            shortcuts.setOpenMediaAction(nil)
            shortcuts.setOpenCollectionAction(nil)
            shortcuts.setOpenPersonAction(nil)
            for number in 1...6 {
                shortcuts.setFixedAction(.navigation(number), action: nil)
            }
            for section in CineLarkSection.allCases {
                shortcuts.setSectionAction(section, action: nil)
            }
            shortcuts.setFixedAction(.refresh, action: nil)
        }
        .onChange(of: store.selection) {
            switch store.selection {
            case .home: shortcuts.reportSection(.home)
            case .movies: shortcuts.reportSection(.movies)
            case .series: shortcuts.reportSection(.series)
            case .favorites: shortcuts.reportSection(.favorites)
            case .search: shortcuts.reportSection(.search)
            case .insights: shortcuts.reportSection(.insights)
            }
        }
        .onChange(of: store.sidebarVisible) {
            actualColumnVisibility = store.sidebarVisible ? .all : .detailOnly
        }
        .onExitCommand {
            shortcuts.navigateBack()
        }
    }

    private var selection: Binding<LibrarySelection?> {
        Binding(
            get: { store.selection },
            set: { value in
                guard let value else { return }
                store.send(.view(.sectionSelected(value)))
            }
        )
    }

    private func navigationLink(
        _ value: LibrarySelection,
        titleKey: String,
        symbol: String,
        shortcut: Int
    ) -> some View {
        NavigationLink(value: value) {
            Label(
                language.localized(titleKey),
                systemImage: store.selection == value && symbol != "magnifyingglass"
                    ? "\(symbol).fill"
                    : symbol
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .cineLarkShortcut(.command(shortcut))
    }

    @ViewBuilder
    private var destination: some View {
        switch store.selection {
        case .home:
            CatalogHomeView(store: libraryStore)
        case .movies:
            CatalogCategoryView(kind: .movie, store: libraryStore)
        case .series:
            CatalogCategoryView(kind: .series, store: libraryStore)
        case .favorites:
            CatalogFavoritesView(store: libraryStore)
        case .search:
            SearchView(store: searchStore)
        case .insights:
            InsightsView(store: insightsStore)
        }
    }
}
