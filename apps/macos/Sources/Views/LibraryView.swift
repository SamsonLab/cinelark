import SwiftUI
import CineLarkDomain

private enum LibrarySelection: Hashable {
    case home
    case movies
    case series
    case favorites
    case search
}

struct LibraryView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel
    @State private var selection: LibrarySelection? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Namespace private var mediaTransitionNamespace

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Section {
                        navigationLink(.home, titleKey: "nav.home", symbol: "house")
                        navigationLink(.movies, titleKey: "nav.movies", symbol: "film.stack")
                        navigationLink(.series, titleKey: "nav.series", symbol: "tv")
                        navigationLink(.favorites, titleKey: "nav.favorites", symbol: "heart")
                        navigationLink(.search, titleKey: "nav.search", symbol: "magnifyingglass")
                    }
                }
                .listStyle(.sidebar)

                Divider()

                sidebarUtilities
            }
            .navigationTitle("CineLark")
            .navigationSplitViewColumnWidth(min: 190, ideal: 228, max: 280)
        } detail: {
            NavigationStack {
                destination
                    .navigationDestination(for: MediaSummary.self) { item in
                        MediaDetailView(
                            item: item,
                            provider: model.provider,
                            playback: model.playback
                        )
                        .onAppear { columnVisibility = .detailOnly }
                        .onDisappear { columnVisibility = .all }
                    }
                    .navigationDestination(for: MediaDetailRoute.self) { route in
                        MediaDetailView(
                            item: route.item,
                            provider: model.provider,
                            playback: model.playback,
                            transitionID: route.transitionID
                        )
                        .onAppear { columnVisibility = .detailOnly }
                        .onDisappear { columnVisibility = .all }
                    }
                    .navigationDestination(for: MediaCollection.self) { collection in
                        CollectionView(collection: collection, model: model)
                    }
                    .navigationDestination(for: PersonCredit.self) { person in
                        PersonDetailView(person: person, provider: model.provider)
                            .onAppear { columnVisibility = .detailOnly }
                            .onDisappear { columnVisibility = .all }
                    }
            }
            .environment(\.mediaTransitionNamespace, mediaTransitionNamespace)
            .background(CineLarkPageBackground())
        }
        .navigationSplitViewStyle(.prominentDetail)
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
            Button(language.localized("general.dismiss"), role: .cancel) {
                model.dismissError()
            }
        } message: {
            Text(language.userFacingError(model.errorMessage))
        }
    }

    private var sidebarUtilities: some View {
        VStack(spacing: 6) {
            LanguageMenu()
                .buttonStyle(.plain)
                .sidebarUtilitySurface()

            Button {
                Task { await model.refreshHome() }
            } label: {
                Label(
                    language.localized("general.refresh"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
            .sidebarUtilitySurface()
            .disabled(model.isLoadingHome)

            Button {
                Task { await model.signOut() }
            } label: {
                Label(
                    language.localized("nav.sign_out"),
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .sidebarUtilitySurface()

            Text(appVersionLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 2)
        }
        .padding(12)
    }

    private var appVersionLabel: String {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return "CineLark"
        }
        return "CineLark v\(version)"
    }

    private func navigationLink(
        _ value: LibrarySelection,
        titleKey: String,
        symbol: String
    ) -> some View {
        NavigationLink(value: value) {
            Label(
                language.localized(titleKey),
                systemImage: selection == value && symbol != "magnifyingglass"
                    ? "\(symbol).fill"
                    : symbol
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
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
        }
    }
}

private extension View {
    func sidebarUtilitySurface() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
            .cineLarkHoverSurface(
                cornerRadius: 10,
                normalFillOpacity: 0,
                hoverFillOpacity: 0.10,
                normalStrokeOpacity: 0,
                hoverStrokeOpacity: 0.08
            )
    }
}
