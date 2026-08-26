import ComposableArchitecture
import SwiftUI

struct CatalogPersonDetailView: View {
    @Bindable var store: StoreOf<PersonDetailFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CineLarkPageHeader(store.detail?.name ?? store.initialPerson.name)
            if store.isLoading && store.works.isEmpty {
                ProgressView("Loading credits…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.works.isEmpty {
                ContentUnavailableView("No credits available", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PosterGrid(items: store.works)
            }
        }
        .background(CineLarkPageBackground())
        .navigationTitle(store.detail?.name ?? store.initialPerson.name)
        .task { store.send(.view(.appeared)) }
    }
}
