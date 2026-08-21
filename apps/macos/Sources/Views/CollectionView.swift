import SwiftUI
import CineLarkDomain

struct CollectionView: View {
    let collection: MediaCollection
    @Bindable var model: AppModel
    @State private var sortField: MediaSort.Field = .releaseDate
    @State private var sortOrder: MediaSort.Order = .descending

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(collection.name)
                    .font(CineLarkDesign.Typography.pageTitle)
                Text(collection.itemCount.formatted())
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
            .padding(.top, CineLarkDesign.Layout.pageTopInset)
            .padding(.bottom, 8)

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
                    Text(title)
                        .font(CineLarkDesign.Typography.pageTitle)
                        .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
                        .padding(.top, CineLarkDesign.Layout.pageTopInset)
                        .padding(.bottom, 18)

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
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(collections) { collection in
                    CollectionFilterButton(
                        collection: collection,
                        isSelected: selectedCollection?.id == collection.id
                    ) {
                        selectedCollectionID = collection.id
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .contentMargins(
            .horizontal,
            CineLarkDesign.Layout.contentMargin,
            for: .scrollContent
        )
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .focusSection()
    }

    private var sort: MediaSort {
        MediaSort(field: sortField, order: sortOrder)
    }

    private var title: String {
        language.localized(kind == .movie ? "nav.movies" : "nav.series")
    }
}

private struct CollectionFilterButton: View {
    @Environment(\.appLanguage) private var language
    let collection: MediaCollection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) {
                Label(
                    "\(collection.name)  \(collection.itemCount.formatted())",
                    systemImage: "checkmark"
                )
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .accessibilityValue(language.localized("general.selected"))
        } else {
            Button(action: action) {
                Text("\(collection.name)  \(collection.itemCount.formatted())")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .accessibilityValue(language.localized("general.not_selected"))
        }
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
                    } label: {
                        if field == option {
                            Label(option.displayName(language: language), systemImage: "checkmark")
                        } else {
                            Text(option.displayName(language: language))
                        }
                    }
                }
            } label: {
                Label(field.displayName(language: language), systemImage: "arrow.up.arrow.down")
            }
            .help(language.localized("sort.label"))

            Button {
                order = order == .ascending ? .descending : .ascending
            } label: {
                Image(systemName: order == .ascending ? "arrow.up" : "arrow.down")
            }
            .accessibilityLabel(
                language.localized(order == .ascending ? "sort.ascending" : "sort.descending")
            )
            .help(
                language.localized(
                    order == .ascending ? "sort.ascending_help" : "sort.descending_help"
                )
            )
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
