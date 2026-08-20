import SwiftUI
import CineLarkDomain

struct CollectionView: View {
    let collection: MediaCollection
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.loadingCollectionID == collection.id && items.isEmpty {
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
        .navigationTitle(collection.name)
        .task(id: collection.id) {
            await model.loadCollection(collection)
        }
    }

    private var items: [MediaSummary] {
        model.collectionItems[collection.id] ?? []
    }
}
