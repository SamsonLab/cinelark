import SwiftUI
import CineLarkDomain

struct CollectionView: View {
    let collection: MediaCollection
    @Bindable var model: AppModel
    @State private var sortField: MediaSort.Field = .releaseDate
    @State private var sortOrder: MediaSort.Order = .descending

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CineLarkPageHeader(
                collection.name,
                subtitle: collection.itemCount.formatted()
            )

            CollectionBrowserContent(collection: collection, sort: sort, model: model)
        }
        .background(CineLarkPageBackground())
        .navigationTitle(collection.name)
        .toolbar {
            MediaSortToolbar(field: $sortField, order: $sortOrder)
        }
    }

    private var sort: MediaSort {
        MediaSort(field: sortField, order: sortOrder)
    }
}

struct MediaCategoryView: View {
    @Environment(\.appLanguage) private var language
    let kind: MediaKind
    @Bindable var model: AppModel
    @State private var selectedCollectionID: String?
    @State private var sortField: MediaSort.Field = .releaseDate
    @State private var sortOrder: MediaSort.Order = .descending

    var body: some View {
        Group {
            if let selectedCollection {
                VStack(alignment: .leading, spacing: 0) {
                    CineLarkPageHeader(title)

                    collectionSelector

                    CollectionBrowserContent(
                        collection: selectedCollection,
                        sort: sort,
                        model: model
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CineLarkPageBackground())
        .navigationTitle(title)
        .toolbar {
            MediaSortToolbar(field: $sortField, order: $sortOrder)
        }
    }

    private var collections: [MediaCollection] {
        model.collections.filter { $0.mediaKind == kind }
    }

    private var selectedCollection: MediaCollection? {
        if let selectedCollectionID,
           let collection = collections.first(where: { $0.id == selectedCollectionID }) {
            return collection
        }
        return collections.first
    }

    private var collectionSelector: some View {
        CineLarkFilterBar {
            ForEach(collections) { collection in
                CineLarkFilterButton(
                    title: collection.name,
                    count: collection.itemCount,
                    isSelected: selectedCollection?.id == collection.id
                ) {
                    selectedCollectionID = collection.id
                }
            }
        }
    }

    private var sort: MediaSort {
        MediaSort(field: sortField, order: sortOrder)
    }

    private var title: String {
        language.localized(kind == .movie ? "nav.movies" : "nav.series")
    }
}

private struct CollectionBrowserContent: View {
    @Environment(\.appLanguage) private var language
    let collection: MediaCollection
    let sort: MediaSort
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.isLoading(collection, sort: sort) && items.isEmpty {
                ProgressView(language.localized("collection.loading", collection.name))
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    language.localized("collection.empty"),
                    systemImage: "rectangle.stack",
                    description: Text(language.localized("collection.empty_description"))
                )
            } else {
                PosterGrid(
                    items: items,
                    isLoadingMore: model.isLoading(collection, sort: sort),
                    canLoadMore: model.canLoadMore(collection, sort: sort),
                    onLoadMore: {
                        await model.loadMore(in: collection, sort: sort)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: requestID) {
            await model.loadCollection(collection, sort: sort)
        }
    }

    private var items: [MediaSummary] {
        model.items(in: collection, sort: sort)
    }

    private var requestID: String {
        [collection.id, sort.field.rawValue, sort.order.rawValue].joined(separator: ":")
    }
}

private struct MediaSortToolbar: ToolbarContent {
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
                HStack(spacing: 7) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(field.displayName(language: language))
                }
                .font(.callout.weight(.semibold))
                .fixedSize()
            }
            .buttonStyle(.glass)
            .accessibilityLabel(sortFieldAccessibilityLabel)
            .help(sortFieldAccessibilityLabel)

            Button {
                toggleOrder()
            } label: {
                HStack(spacing: 7) {
                    Text(orderDisplayName)
                    Image(systemName: orderIcon)
                }
                .font(.callout.weight(.semibold))
                .fixedSize()
            }
            .buttonStyle(.glass)
            .accessibilityLabel(orderDisplayName)
            .help(
                language.localized(
                    order == .ascending ? "sort.descending_help" : "sort.ascending_help"
                )
            )
        }
    }

    private var orderIcon: String {
        order == .ascending ? "arrow.up" : "arrow.down"
    }

    private var sortFieldAccessibilityLabel: String {
        [
            language.localized("sort.label"),
            field.displayName(language: language)
        ]
        .joined(separator: ", ")
    }

    private var orderDisplayName: String {
        language.localized(order == .ascending ? "sort.ascending" : "sort.descending")
    }

    private func toggleOrder() {
        order = order == .ascending ? .descending : .ascending
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
