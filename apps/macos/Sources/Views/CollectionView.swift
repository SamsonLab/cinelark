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
    @Environment(\.appLanguage) private var language
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
                    language.localized(
                        kind == .movie
                            ? "category.no_movie_collections"
                            : "category.no_series_collections"
                    ),
                    systemImage: kind == .movie ? "film.stack" : "tv",
                    description: Text(
                        language.localized("category.no_collections_description")
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    Button {
                        selectedCollectionID = collection.id
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .opacity(selectedCollection?.id == collection.id ? 1 : 0)
                                .frame(width: 12)
                                .accessibilityHidden(true)
                            Text(collection.name)
                            Text(collection.itemCount.formatted())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            selectedCollection?.id == collection.id
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear,
                            in: Capsule()
                        )
                        .cineLarkHoverSurface(
                            cornerRadius: 999,
                            normalFillOpacity: selectedCollection?.id == collection.id ? 0.04 : 0.055,
                            normalStrokeOpacity: 0,
                            hoverStrokeOpacity: 0
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        language.localized(
                            selectedCollection?.id == collection.id
                                ? "general.selected"
                                : "general.not_selected"
                        )
                    )
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
                ProgressView(
                    language.localized("collection.loading", collection.name)
                )
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    language.localized("collection.empty"),
                    systemImage: "rectangle.stack",
                    description: Text(
                        language.localized("collection.empty_description")
                    )
                )
            } else {
                MediaGrid(items: items)
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
        [
            collection.id,
            sort.field.rawValue,
            sort.order.rawValue
        ].joined(separator: ":")
    }
}

private struct MediaSortToolbar: ToolbarContent {
    @Environment(\.appLanguage) private var language
    @Binding var field: MediaSort.Field
    @Binding var order: MediaSort.Order

    var body: some ToolbarContent {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            toolbarItem
                .sharedBackgroundVisibility(.hidden)
        } else {
            toolbarItem
        }
        #else
        toolbarItem
        #endif
    }

    private var toolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 4) {
                SortFieldPickerButton(field: $field)

                Button {
                    order = order == .ascending ? .descending : .ascending
                } label: {
                    Image(systemName: order == .ascending ? "arrow.up" : "arrow.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .cineLarkHoverSurface(
                            cornerRadius: 18,
                            normalFillOpacity: 0,
                            normalStrokeOpacity: 0,
                            hoverStrokeOpacity: 0
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    language.localized(
                        order == .ascending
                            ? "sort.ascending"
                            : "sort.descending"
                    )
                )
                .help(
                    language.localized(
                        order == .ascending
                            ? "sort.ascending_help"
                            : "sort.descending_help"
                    )
                )
            }
            .padding(.horizontal, 4)
            .frame(height: 44, alignment: .center)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .fixedSize()
        }
    }
}

private struct SortFieldPickerButton: View {
    @Environment(\.appLanguage) private var language
    @Binding var field: MediaSort.Field
    @State private var isPresentingOptions = false

    var body: some View {
        Button {
            isPresentingOptions.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(field.displayName(language: language))
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(width: 176, height: 36)
            .cineLarkHoverSurface(
                cornerRadius: 18,
                normalFillOpacity: 0,
                normalStrokeOpacity: 0,
                hoverStrokeOpacity: 0
            )
        }
        .buttonStyle(.plain)
        .help(language.localized("sort.label"))
        .popover(isPresented: $isPresentingOptions, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(MediaSort.Field.allCases, id: \.self) { option in
                    Button {
                        field = option
                        isPresentingOptions = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .opacity(field == option ? 1 : 0)
                                .frame(width: 14)
                                .accessibilityHidden(true)
                            Text(option.displayName(language: language))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        language.localized(
                            field == option
                                ? "general.selected"
                                : "general.not_selected"
                        )
                    )
                    .cineLarkHoverSurface(
                        cornerRadius: 7,
                        normalFillOpacity: 0,
                        normalStrokeOpacity: 0,
                        hoverStrokeOpacity: 0
                    )
                }
            }
            .padding(8)
            .frame(width: 220)
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
