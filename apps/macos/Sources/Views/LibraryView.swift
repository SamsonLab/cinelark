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
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel
    @State private var selection: LibrarySelection? = .home

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    NavigationLink(value: LibrarySelection.home) {
                        Label(language.localized("nav.home"), systemImage: "house.fill")
                    }
                    NavigationLink(value: LibrarySelection.movies) {
                        Label(language.localized("nav.movies"), systemImage: "film.stack.fill")
                    }
                    NavigationLink(value: LibrarySelection.series) {
                        Label(language.localized("nav.series"), systemImage: "tv.fill")
                    }
                    NavigationLink(value: LibrarySelection.favorites) {
                        Label(language.localized("nav.favorites"), systemImage: "heart.fill")
                    }
                    NavigationLink(value: LibrarySelection.search) {
                        Label(language.localized("nav.search"), systemImage: "magnifyingglass")
                    }
                }

                if !model.collections.isEmpty {
                    Section(language.localized("nav.collections")) {
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
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    LanguageMenu()
                        .menuStyle(.borderlessButton)
                    Button {
                        Task { await model.signOut() }
                    } label: {
                        Label(
                            language.localized("nav.sign_out"),
                            systemImage: "rectangle.portrait.and.arrow.right"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
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
            Button(language.localized("general.ok"), role: .cancel) { model.dismissError() }
        } message: {
            Text(language.userFacingError(model.errorMessage))
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
                ContentUnavailableView(
                    language.localized("nav.collection_unavailable"),
                    systemImage: "rectangle.stack"
                )
            }
        }
    }
}
