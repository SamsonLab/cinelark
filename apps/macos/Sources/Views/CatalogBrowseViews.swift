import ComposableArchitecture
import SwiftUI
import CineLarkDomain
import CineLarkProfile

struct CatalogContinueWatchingShelf: View {
    @Environment(\.appLanguage) private var language
    @Environment(ShortcutCoordinator.self) private var shortcuts
    let items: [LibraryFeature.FavoriteSnapshot]
    @Bindable var store: StoreOf<LibraryFeature>
    let selectedItemID: ProfileMediaKey?
    let isKeyboardNavigationActive: Bool
    let onPointerSelection: (LibraryFeature.FavoriteSnapshot, Bool) -> Void
    let onHighlight: (LibraryFeature.FavoriteSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.localized("home.continue_watching"))
                .font(CineLarkDesign.Typography.sectionTitle)
                .padding(.horizontal, CineLarkDesign.Layout.contentMargin)

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: CineLarkDesign.Layout.shelfSpacing) {
                        ForEach(items) { item in
                            Button {
                                store.send(.view(.playResume(item)))
                            } label: {
                                VStack(
                                    alignment: .leading,
                                    spacing: CineLarkDesign.Layout.lockupSpacing
                                ) {
                                    ZStack {
                                        MediaArtworkSurface(
                                            item: item.summary,
                                            url: item.summary.backdropURL ?? item.summary.posterURL,
                                            locator: item.locator,
                                            size: CGSize(
                                                width: CineLarkDesign.Media.landscapeWidth,
                                                height: CineLarkDesign.Media.landscapeHeight
                                            ),
                                            role: .playback
                                        )

                                        Image(systemName: "play.fill")
                                            .font(.system(size: 21, weight: .semibold))
                                            .frame(width: 54, height: 54)
                                            .background(
                                                CineLarkDesign.Palette.badgeBackground,
                                                in: Circle()
                                            )
                                    }

                                    Text(item.summary.title)
                                        .font(CineLarkDesign.Typography.cardTitle)
                                        .lineLimit(1)

                                    Text(language.progressPercent(item.summary.userState.progress))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(
                                    width: CineLarkDesign.Media.landscapeWidth,
                                    alignment: .leading
                                )
                            }
                            .buttonStyle(CineLarkPressButtonStyle())
                            .focusEffectDisabled()
                            .cineLarkFocusSurface(
                                isActive: shortcuts.usesKeyboardNavigation &&
                                    isKeyboardNavigationActive &&
                                    selectedItemID == item.id,
                                cornerRadius: CineLarkDesign.Shape.cardRadius
                            )
                            .cineLarkPointerSelection { hovering in
                                onPointerSelection(item, hovering)
                                if hovering { onHighlight(item) }
                            }
                            .id(item.id)
                        }
                    }
                    .padding(.vertical, 26)
                }
                .contentMargins(
                    .horizontal,
                    CineLarkDesign.Layout.contentMargin,
                    for: .scrollContent
                )
                .scrollTargetBehavior(.viewAligned)
                .cineLarkHorizontalScrollIndicatorsHidden()
                .onChange(of: selectedItemID) {
                    guard let selectedItemID else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo(selectedItemID, anchor: .leading)
                    }
                }
            }
        }
    }
}

struct CatalogCategoryView: View {
    @Environment(\.appLanguage) private var language
    let kind: MediaKind
    @Bindable var store: StoreOf<LibraryFeature>
    @State private var selectedCollectionID: String?
    @State private var keyboardSelectedCollectionID: String?
    @State private var pointerSelectedCollectionID: String?
    @State private var sortField: MediaSort.Field = .releaseDate
    @State private var sortOrder: MediaSort.Order = .descending

    var body: some View {
        Group {
            if let selectedCollection {
                VStack(alignment: .leading, spacing: 0) {
                    CineLarkPageHeader(title)
                    collectionSelector
                    CatalogCollectionContent(
                        store: store,
                        pointerSelectedLeadingActionID: pointerSelectedCollectionID,
                        preferredLeadingKeyboardID: selectedCollection.id,
                        leadingKeyboardActions: collectionKeyboardActions,
                        onLeadingSelectionChange: {
                            keyboardSelectedCollectionID = $0
                        }
                    )
                }
            } else {
                ContentUnavailableView(
                    language.localized(
                        kind == .movie
                            ? "category.no_movie_collections"
                            : "category.no_series_collections"
                    ),
                    systemImage: kind == .movie ? "film.stack" : "tv",
                    description: Text(language.localized("category.no_collections_description"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CineLarkPageBackground())
        .navigationTitle(title)
        .task(id: requestIdentity) { loadSelection() }
        .toolbar {
            CatalogSortToolbar(field: $sortField, order: $sortOrder)
        }
    }

    private var collections: [MediaCollection] {
        store.collections.filter { $0.mediaKind == kind }
    }

    private var selectedCollection: MediaCollection? {
        if let selectedCollectionID,
           let value = collections.first(where: { $0.id == selectedCollectionID }) {
            return value
        }
        return collections.first
    }

    private var collectionSelector: some View {
        CineLarkFilterBar(selectedID: keyboardSelectedCollectionID) {
            ForEach(collections) { collection in
                CineLarkFilterButton(
                    title: collection.name,
                    count: collection.itemCount,
                    isSelected: selectedCollection?.id == collection.id,
                    isKeyboardSelected: keyboardSelectedCollectionID == collection.id,
                    onPointerSelection: { hovering in
                        if hovering {
                            pointerSelectedCollectionID = collection.id
                        } else if pointerSelectedCollectionID == collection.id {
                            pointerSelectedCollectionID = nil
                        }
                    }
                ) {
                    selectedCollectionID = collection.id
                }
                .id(collection.id)
            }
        }
    }

    private var sort: MediaSort { MediaSort(field: sortField, order: sortOrder) }

    private var requestIdentity: String {
        [selectedCollection?.id ?? "", sortField.rawValue, sortOrder.rawValue]
            .joined(separator: ":")
    }

    private func loadSelection() {
        guard let selectedCollection else { return }
        store.send(.view(.loadCollection(selectedCollection, sort)))
    }

    private var collectionKeyboardActions: [PosterGridLeadingKeyboardAction] {
        collections.map { collection in
            PosterGridLeadingKeyboardAction(id: collection.id) {
                selectedCollectionID = collection.id
                return true
            }
        }
    }

    private var title: String {
        language.localized(kind == .movie ? "nav.movies" : "nav.series")
    }
}

struct CatalogCollectionView: View {
    let collection: MediaCollection
    @Bindable var store: StoreOf<LibraryFeature>
    @State private var sortField: MediaSort.Field = .releaseDate
    @State private var sortOrder: MediaSort.Order = .descending

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CineLarkPageHeader(collection.name, subtitle: collection.itemCount.formatted())
            CatalogCollectionContent(store: store, navigationLevel: .route)
        }
        .background(CineLarkPageBackground())
        .navigationTitle(collection.name)
        .task(id: requestIdentity) {
            store.send(.view(.loadCollection(
                collection,
                MediaSort(field: sortField, order: sortOrder)
            )))
        }
        .toolbar {
            CatalogSortToolbar(field: $sortField, order: $sortOrder)
        }
    }

    private var requestIdentity: String {
        [collection.id, sortField.rawValue, sortOrder.rawValue].joined(separator: ":")
    }
}

private struct CatalogCollectionContent: View {
    @Environment(\.appLanguage) private var language
    @Bindable var store: StoreOf<LibraryFeature>
    var navigationLevel: CineLarkNavigationSurfaceLevel = .page
    var pointerSelectedLeadingActionID: String? = nil
    var preferredLeadingKeyboardID: String? = nil
    var leadingKeyboardActions: [PosterGridLeadingKeyboardAction] = []
    var onLeadingSelectionChange: ((String?) -> Void)? = nil

    var body: some View {
        ZStack {
            PosterGrid(
                items: store.orderedItems.map(\.summary),
                isLoadingMore: store.isLoadingMore,
                canLoadMore: store.nextCursor != nil,
                navigationLevel: navigationLevel,
                pointerSelectedLeadingActionID: pointerSelectedLeadingActionID,
                preferredLeadingKeyboardID: preferredLeadingKeyboardID,
                leadingKeyboardActions: leadingKeyboardActions,
                onLeadingSelectionChange: onLeadingSelectionChange,
                onLoadMore: {
                    await store.send(.view(.loadMore)).finish()
                }
            )
            if store.isRefreshing && store.orderedItems.isEmpty {
                ProgressView(language.localized("home.loading"))
                    .controlSize(.large)
            } else if !store.isRefreshing && store.orderedItems.isEmpty {
                ContentUnavailableView(
                    language.localized("collection.empty"),
                    systemImage: "rectangle.stack",
                    description: Text(language.localized("collection.empty_description"))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CatalogFavoritesView: View {
    private enum Tab: CaseIterable, Equatable, Identifiable {
        case series
        case movies

        var id: Self { self }

        var keyboardID: String {
            switch self {
            case .series: "favorites.series"
            case .movies: "favorites.movies"
            }
        }

        var kind: MediaKind {
            switch self {
            case .series: .series
            case .movies: .movie
            }
        }

        func title(language: AppLanguage) -> String {
            language.localized(
                self == .series ? "favorites.series" : "favorites.movies"
            )
        }
    }

    @Environment(\.appLanguage) private var language
    @Bindable var store: StoreOf<LibraryFeature>
    @State private var selectedTab: Tab = .series
    @State private var keyboardSelectedTabID: String?
    @State private var pointerSelectedTabID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CineLarkPageHeader(language.localized("favorites.title"))
            favoriteSelector

            ZStack {
                PosterGrid(
                    items: items,
                    topContentInset: CineLarkDesign.Layout.focusSafeTopInset,
                    pointerSelectedLeadingActionID: pointerSelectedTabID,
                    preferredLeadingKeyboardID: selectedTab.keyboardID,
                    leadingKeyboardActions: tabKeyboardActions,
                    onLeadingSelectionChange: { keyboardSelectedTabID = $0 }
                )
                if items.isEmpty {
                    ContentUnavailableView(
                        language.localized(
                            selectedTab == .series
                                ? "favorites.no_series"
                                : "favorites.no_movies"
                        ),
                        systemImage: "heart",
                        description: Text(language.localized("favorites.no_media_description"))
                    )
                }
            }
        }
        .background(CineLarkPageBackground())
        .navigationTitle(language.localized("favorites.title"))
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

    private var items: [MediaSummary] {
        store.favorites.map(\.summary).filter { $0.kind == selectedTab.kind }
    }

    private func count(for tab: Tab) -> Int {
        store.favorites.lazy.filter { $0.summary.kind == tab.kind }.count
    }

    private var tabKeyboardActions: [PosterGridLeadingKeyboardAction] {
        Tab.allCases.map { tab in
            PosterGridLeadingKeyboardAction(id: tab.keyboardID) {
                selectedTab = tab
                return true
            }
        }
    }
}

private struct CatalogSortToolbar: ToolbarContent {
    @Environment(\.appLanguage) private var language
    @Binding var field: MediaSort.Field
    @Binding var order: MediaSort.Order

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(MediaSort.Field.allCases, id: \.self) { option in
                    Button {
                        field = option
                        order = .descending
                    } label: {
                        if field == option {
                            Label(
                                option.displayName(language: language),
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(option.displayName(language: language))
                        }
                    }
                }
            } label: {
                Label(
                    field.displayName(language: language),
                    systemImage: "arrow.up.arrow.down"
                )
                .font(.callout.weight(.semibold))
            }
            .buttonStyle(.glass)

            Button {
                order = order == .ascending ? .descending : .ascending
            } label: {
                Label(
                    language.localized(
                        order == .ascending ? "sort.ascending" : "sort.descending"
                    ),
                    systemImage: order == .ascending ? "arrow.up" : "arrow.down"
                )
                .font(.callout.weight(.semibold))
            }
            .buttonStyle(.glass)
            .help(language.localized(
                order == .ascending ? "sort.descending_help" : "sort.ascending_help"
            ))
        }
    }
}

private extension MediaSort.Field {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .releaseDate: language.localized("sort.release_date")
        case .title: language.localized("sort.name")
        case .rating: language.localized("sort.rating")
        case .updatedAt: language.localized("sort.updated_date")
        case .assetUpdatedAt: language.localized("sort.asset_updated")
        case .popularity: language.localized("sort.popularity")
        }
    }
}
