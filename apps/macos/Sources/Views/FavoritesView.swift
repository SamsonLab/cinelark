import SwiftUI
import CineLarkDomain

struct FavoritesView: View {
    private enum Tab: CaseIterable, Identifiable {
        case series
        case movies
        case people

        var id: Self { self }

        func title(language: AppLanguage) -> String {
            switch self {
            case .series: language.localized("favorites.series")
            case .movies: language.localized("favorites.movies")
            case .people: language.localized("favorites.people")
            }
        }
    }

    @Environment(\.appLanguage) private var language
    @State private var model: FavoritesModel
    @State private var selectedTab: Tab = .series

    init(provider: any MediaLibraryProvider) {
        _model = State(initialValue: FavoritesModel(provider: provider))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CineLarkPageHeader(language.localized("favorites.title"))
            favoriteSelector
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CineLarkPageBackground())
        .navigationTitle(language.localized("favorites.title"))
        .task {
            await model.load()
        }
        .alert(
            "CineLark",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button(language.localized("general.dismiss"), role: .cancel) { model.dismissError() }
        } message: {
            Text(language.userFacingError(model.errorMessage))
        }
    }

    private var favoriteSelector: some View {
        CineLarkFilterBar {
            ForEach(Tab.allCases) { tab in
                CineLarkFilterButton(
                    title: tab.title(language: language),
                    count: count(for: tab),
                    isSelected: selectedTab == tab
                ) {
                    selectedTab = tab
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.movies.isEmpty && model.series.isEmpty && model.people.isEmpty {
            ProgressView(language.localized("favorites.loading"))
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch selectedTab {
            case .series:
                mediaContent(model.series, emptyKey: "favorites.no_series")
            case .movies:
                mediaContent(model.movies, emptyKey: "favorites.no_movies")
            case .people:
                peopleContent
            }
        }
    }

    @ViewBuilder
    private func mediaContent(_ items: [MediaSummary], emptyKey: String) -> some View {
        if items.isEmpty {
            ContentUnavailableView(
                language.localized(emptyKey),
                systemImage: "heart",
                description: Text(language.localized("favorites.no_media_description"))
            )
        } else {
            PosterGrid(items: items)
        }
    }

    @ViewBuilder
    private var peopleContent: some View {
        if model.people.isEmpty {
            ContentUnavailableView(
                language.localized("favorites.no_people"),
                systemImage: "person.crop.circle",
                description: Text(language.localized("favorites.no_people_description"))
            )
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(
                                minimum: CineLarkDesign.Media.posterWidth,
                                maximum: CineLarkDesign.Media.posterWidth + 26
                            ),
                            spacing: CineLarkDesign.Layout.posterGridColumnSpacing,
                            alignment: .top
                        )
                    ],
                    spacing: CineLarkDesign.Layout.posterGridRowSpacing
                ) {
                    ForEach(model.people) { person in
                        FavoritePersonLink(
                            person: person,
                            credit: credit(for: person)
                        )
                    }
                }
                .focusSection()
                .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
                .padding(.vertical, 34)
            }
        }
    }

    private func count(for tab: Tab) -> Int {
        switch tab {
        case .series: model.seriesCount
        case .movies: model.movieCount
        case .people: model.peopleCount
        }
    }

    private func credit(for person: PersonDetail) -> PersonCredit {
        PersonCredit(
            id: person.id,
            name: person.name,
            character: nil,
            avatarURL: person.avatarURL,
            order: nil
        )
    }
}

private struct FavoritePersonLink: View {
    let person: PersonDetail
    let credit: PersonCredit
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(value: credit) {
            VStack(spacing: 12) {
                ArtworkView(url: person.avatarURL)
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular, in: Circle())
                    }
                    .cineLarkFocusSurface(
                        isActive: isHovering || isFocused,
                        cornerRadius: 75,
                        scale: 1.05
                    )
                Text(person.name)
                    .font(CineLarkDesign.Typography.cardTitle)
                    .lineLimit(1)
            }
            .frame(width: CineLarkDesign.Media.posterWidth)
        }
        .buttonStyle(CineLarkPressButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }
}
