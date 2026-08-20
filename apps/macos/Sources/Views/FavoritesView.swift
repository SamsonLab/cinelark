import SwiftUI
import CineLarkDomain

struct FavoritesView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case series = "TV Series"
        case movies = "Movies"
        case people = "People"

        var id: Self { self }
    }

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
        .navigationTitle("Favorites")
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
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Label("My Library", systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Favorites")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text(
                    "\(model.movieCount + model.seriesCount) titles · " +
                    "\(model.peopleCount) people"
                )
                .foregroundStyle(.secondary)
            }

            Picker("Favorite type", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text("\(tab.rawValue)  \(count(for: tab))").tag(tab)
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
            ProgressView("Loading favorites…")
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch selectedTab {
            case .series:
                mediaContent(model.series, label: "TV series")
            case .movies:
                mediaContent(model.movies, label: "movies")
            case .people:
                peopleContent
            }
        }
    }

    @ViewBuilder
    private func mediaContent(_ items: [MediaSummary], label: String) -> some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No favorite \(label)",
                systemImage: "heart",
                description: Text("Titles you favorite will appear here.")
            )
        } else {
            MediaGrid(items: items)
        }
    }

    @ViewBuilder
    private var peopleContent: some View {
        if model.people.isEmpty {
            ContentUnavailableView(
                "No favorite people",
                systemImage: "person.crop.circle",
                description: Text("Cast and crew you favorite will appear here.")
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
