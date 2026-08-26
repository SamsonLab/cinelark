import ComposableArchitecture
import SwiftUI
import CineLarkDomain

struct CatalogHomeView: View {
    @Bindable var store: StoreOf<LibraryFeature>

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 42) {
                CineLarkPageHeader("Home")

                if store.isLoadingOverview,
                   store.latestItems.isEmpty,
                   store.resumeItems.isEmpty {
                    ProgressView("Loading library…")
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 220)
                }

                if !store.resumeItems.isEmpty {
                    PosterShelf(
                        title: "Continue Watching",
                        items: store.resumeItems.map(\.summary)
                    )
                }

                if !store.latestItems.isEmpty {
                    PosterShelf(
                        title: "Latest",
                        items: store.latestItems.map(\.summary)
                    )
                }

                if !store.collections.isEmpty {
                    collections
                }

                if !store.isLoadingOverview,
                   store.latestItems.isEmpty,
                   store.resumeItems.isEmpty,
                   store.collections.isEmpty {
                    ContentUnavailableView(
                        "No media available",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Choose or configure a media source to load its library.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(.bottom, 64)
        }
        .scrollIndicators(.hidden)
        .background(CineLarkPageBackground())
        .navigationTitle("Home")
        .task { store.send(.view(.loadOverview)) }
    }

    private var collections: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Libraries")
                .font(CineLarkDesign.Typography.sectionTitle)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 16)],
                spacing: 16
            ) {
                ForEach(store.collections) { collection in
                    NavigationLink(
                        state: NavigationFeature.Path.State.collection(
                            CollectionRouteFeature.State(collection: collection)
                        )
                    ) {
                        HStack(spacing: 14) {
                            Image(systemName: collection.mediaKind == .movie ? "film.stack" : "tv")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(collection.name)
                                    .font(.headline)
                                Text("\(collection.itemCount) items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(18)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
    }
}

struct CatalogCategoryView: View {
    let kind: MediaKind
    @Bindable var store: StoreOf<LibraryFeature>
    @State private var selectedCollectionID: String?
    @State private var sortField: MediaSort.Field = .releaseDate
    @State private var sortOrder: MediaSort.Order = .descending

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CineLarkPageHeader(kind == .movie ? "Movies" : "Series")
            if collections.isEmpty {
                ContentUnavailableView(
                    "No \(kind == .movie ? "movie" : "series") libraries",
                    systemImage: kind == .movie ? "film.stack" : "tv"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Picker("Library", selection: selection) {
                    ForEach(collections) { collection in
                        Text(collection.name).tag(collection.id)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
                .padding(.bottom, 14)

                CatalogCollectionContent(store: store)
            }
        }
        .background(CineLarkPageBackground())
        .navigationTitle(kind == .movie ? "Movies" : "Series")
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

    private var selection: Binding<String> {
        Binding(
            get: { selectedCollection?.id ?? "" },
            set: { selectedCollectionID = $0 }
        )
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
}

struct CatalogCollectionView: View {
    let collection: MediaCollection
    @Bindable var store: StoreOf<LibraryFeature>
    @State private var sortField: MediaSort.Field = .releaseDate
    @State private var sortOrder: MediaSort.Order = .descending

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CineLarkPageHeader(collection.name, subtitle: collection.itemCount.formatted())
            CatalogCollectionContent(store: store)
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
    @Bindable var store: StoreOf<LibraryFeature>

    var body: some View {
        ZStack {
            PosterGrid(
                items: store.orderedItems.map(\.summary),
                isLoadingMore: store.isLoadingMore,
                canLoadMore: store.nextCursor != nil,
                onLoadMore: {
                    await store.send(.view(.loadMore)).finish()
                }
            )
            if store.isRefreshing && store.orderedItems.isEmpty {
                ProgressView("Loading collection…")
                    .controlSize(.large)
            } else if !store.isRefreshing && store.orderedItems.isEmpty {
                ContentUnavailableView("Collection is empty", systemImage: "rectangle.stack")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CatalogFavoritesView: View {
    @Bindable var store: StoreOf<LibraryFeature>
    @State private var kind: MediaKind = .movie

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CineLarkPageHeader("Favorites")
            Picker("Type", selection: $kind) {
                Text("Movies").tag(MediaKind.movie)
                Text("Series").tag(MediaKind.series)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
            .padding(.bottom, 14)

            ZStack {
                PosterGrid(items: items)
                if items.isEmpty {
                    ContentUnavailableView(
                        "No favorites",
                        systemImage: "heart",
                        description: Text("Favorites are local-first and isolated by profile.")
                    )
                }
            }
        }
        .background(CineLarkPageBackground())
        .navigationTitle("Favorites")
    }

    private var items: [MediaSummary] {
        store.favorites.map(\.summary).filter { $0.kind == kind }
    }
}

private struct CatalogSortToolbar: ToolbarContent {
    @Binding var field: MediaSort.Field
    @Binding var order: MediaSort.Order

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Sort", selection: $field) {
                ForEach(MediaSort.Field.allCases, id: \.self) { option in
                    Text(option.rawValue.capitalized).tag(option)
                }
            }
            Button {
                order = order == .ascending ? .descending : .ascending
            } label: {
                Image(systemName: order == .ascending ? "arrow.up" : "arrow.down")
            }
            .help(order == .ascending ? "Ascending" : "Descending")
        }
    }
}
