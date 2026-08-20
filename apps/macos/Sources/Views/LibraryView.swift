import SwiftUI
import CineLarkDomain

private enum LibrarySelection: Hashable {
    case home
    case movies
    case series
    case favorites
    case search
    case collection(String)
}

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var selection: LibrarySelection? = .home

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    NavigationLink(value: LibrarySelection.home) {
                        Label("Home", systemImage: "house.fill")
                    }
                    NavigationLink(value: LibrarySelection.movies) {
                        Label("Movies", systemImage: "film.stack.fill")
                    }
                    NavigationLink(value: LibrarySelection.series) {
                        Label("TV Series", systemImage: "tv.fill")
                    }
                    NavigationLink(value: LibrarySelection.favorites) {
                        Label("Favorites", systemImage: "heart.fill")
                    }
                    NavigationLink(value: LibrarySelection.search) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }

                if !model.collections.isEmpty {
                    Section("Collections") {
                        ForEach(model.collections) { collection in
                            NavigationLink(value: LibrarySelection.collection(collection.id)) {
                                Label(collection.name, systemImage: "rectangle.stack.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("CineLark")
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await model.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding()
            }
        } detail: {
            NavigationStack {
                destination
                    .navigationDestination(for: MediaSummary.self) { item in
                        MediaDetailView(
                            item: item,
                            provider: model.provider,
                            playback: model.playback
                        )
                    }
                    .navigationDestination(for: PersonCredit.self) { person in
                        PersonDetailView(person: person, provider: model.provider)
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .alert(
            "CineLark",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch selection ?? .home {
        case .home:
            HomeView(model: model)
        case .movies:
            MediaCategoryView(kind: .movie, model: model)
        case .series:
            MediaCategoryView(kind: .series, model: model)
        case .favorites:
            FavoritesView(provider: model.provider)
        case .search:
            SearchView(model: model)
        case .collection(let id):
            if let collection = model.collections.first(where: { $0.id == id }) {
                CollectionView(collection: collection, model: model)
            } else {
                ContentUnavailableView("Collection unavailable", systemImage: "rectangle.stack")
            }
        }
    }
}
