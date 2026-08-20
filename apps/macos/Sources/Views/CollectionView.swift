import SwiftUI
import CineLarkDomain

struct CollectionView: View {
    let collection: MediaCollection
    @Bindable var model: AppModel
    @State private var sortField: MediaSort.Field = .releaseDate
    @State private var sortOrder: MediaSort.Order = .descending

    var body: some View {
        CollectionBrowserContent(
            collection: collection,
            sort: sort,
            model: model
        )
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
    let kind: MediaKind
    @Bindable var model: AppModel
    @State private var selectedCollectionID: String?
    @State private var sortField: MediaSort.Field = .releaseDate
    @State private var sortOrder: MediaSort.Order = .descending

    var body: some View {
        Group {
            if let selectedCollection {
                VStack(spacing: 0) {
                    collectionSelector
                    Divider()
                    CollectionBrowserContent(
                        collection: selectedCollection,
                        sort: sort,
                        model: model
                    )
                }
            } else {
                ContentUnavailableView(
                    "No \(title.lowercased()) collections",
                    systemImage: kind == .movie ? "film.stack" : "tv",
                    description: Text("The provider did not return a matching collection.")
                )
            }
        }
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
            HStack(spacing: 10) {
                ForEach(collections) { collection in
                    Button {
                        selectedCollectionID = collection.id
                    } label: {
                        HStack(spacing: 7) {
                            Text(collection.name)
                            Text(collection.itemCount.formatted())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedCollection?.id == collection.id
                                ? Color.accentColor.opacity(0.2)
                                : Color.white.opacity(0.06),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    selectedCollection?.id == collection.id
                                        ? Color.accentColor.opacity(0.8)
                                        : Color.white.opacity(0.12)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.opacity(0.86))
    }

    private var sort: MediaSort {
        MediaSort(field: sortField, order: sortOrder)
    }

    private var title: String {
        kind == .movie ? "Movies" : "TV Series"
    }
}

private struct CollectionBrowserContent: View {
    let collection: MediaCollection
    let sort: MediaSort
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.isLoading(collection, sort: sort) && items.isEmpty {
                ProgressView("Loading \(collection.name)…")
                    .controlSize(.large)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No items",
                    systemImage: "rectangle.stack",
                    description: Text("This collection is currently empty.")
                )
            } else {
                MediaGrid(items: items)
            }
        }
        .task(id: requestID) {
            await model.loadCollection(collection, sort: sort)
        }
    }

    private var items: [MediaSummary] {
        model.items(in: collection, sort: sort)
    }

    private var requestID: String {
        [
            collection.id,
            sort.field.rawValue,
            sort.order.rawValue
        ].joined(separator: ":")
    }
}

private struct MediaSortToolbar: ToolbarContent {
    @Binding var field: MediaSort.Field
    @Binding var order: MediaSort.Order

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Sort by", selection: $field) {
                ForEach(MediaSort.Field.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 150)

            Button {
                order = order == .ascending ? .descending : .ascending
            } label: {
                Label(
                    order == .ascending ? "Ascending" : "Descending",
                    systemImage: order == .ascending ? "arrow.up" : "arrow.down"
                )
            }
            .help(order == .ascending ? "Sort ascending" : "Sort descending")
        }
    }
}

private extension MediaSort.Field {
    var displayName: String {
        switch self {
        case .releaseDate: "Release Date"
        case .title: "Name"
        case .rating: "Rating"
        case .updatedAt: "Updated Date"
        case .assetUpdatedAt: "Asset Updated"
        case .popularity: "Popularity"
        }
    }
}
