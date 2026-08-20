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
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color.black.opacity(0.92))
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
            Button(language.localized("general.ok"), role: .cancel) { model.dismissError() }
        } message: {
            Text(language.userFacingError(model.errorMessage))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Label(language.localized("favorites.my_library"), systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(language.localized("favorites.title"))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text(
                    language.localized(
                        "favorites.summary",
                        String(model.movieCount + model.seriesCount),
                        String(model.peopleCount)
                    )
                )
                .foregroundStyle(.secondary)
            }

            Picker(language.localized("favorites.type"), selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text("\(tab.title(language: language))  \(count(for: tab))").tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(32)
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
            MediaGrid(items: items)
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
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 28)],
                    spacing: 32
                ) {
                    ForEach(model.people) { person in
                        NavigationLink(value: credit(for: person)) {
                            VStack(spacing: 12) {
                                ArtworkView(url: person.avatarURL)
                                    .frame(width: 150, height: 150)
                                    .clipShape(Circle())
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "heart.fill")
                                            .foregroundStyle(.orange)
                                            .padding(8)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                Text(person.name)
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(32)
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
