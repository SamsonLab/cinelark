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
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Section {
                        NavigationLink(value: LibrarySelection.home) {
                            Label(
                                language.localized("nav.home"),
                                systemImage: selection == .home ? "house.fill" : "house"
                            )
                        }
                        NavigationLink(value: LibrarySelection.movies) {
                            Label(
                                language.localized("nav.movies"),
                                systemImage: selection == .movies ? "film.stack.fill" : "film.stack"
                            )
                        }
                        NavigationLink(value: LibrarySelection.series) {
                            Label(
                                language.localized("nav.series"),
                                systemImage: selection == .series ? "tv.fill" : "tv"
                            )
                        }
                        NavigationLink(value: LibrarySelection.favorites) {
                            Label(
                                language.localized("nav.favorites"),
                                systemImage: selection == .favorites ? "heart.fill" : "heart"
                            )
                        }
                        NavigationLink(value: LibrarySelection.search) {
                            Label(language.localized("nav.search"), systemImage: "magnifyingglass")
                        }
                    }

                    if !model.collections.isEmpty {
                        Section(language.localized("nav.collections")) {
                            ForEach(model.collections) { collection in
                                NavigationLink(value: LibrarySelection.collection(collection.id)) {
                                    Label(
                                        collection.name,
                                        systemImage: selection == .collection(collection.id)
                                            ? "rectangle.stack.fill"
                                            : "rectangle.stack"
                                    )
                                }
                            }
                        }
                    }
                }

                sidebarFooter
            }
            .navigationTitle("CineLark")
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
                    .navigationDestination(for: MediaCollection.self) { collection in
                        CollectionView(collection: collection, model: model)
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
            if model.errorRecovery == .installIINA {
                Button(language.localized("error.download_iina")) {
                    model.performErrorRecovery()
                }
            }
            Button(language.localized("general.dismiss"), role: .cancel) { model.dismissError() }
        } message: {
            Text(language.userFacingError(model.errorMessage))
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(alignment: .leading, spacing: 12) {
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
            .padding(16)
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
