import SwiftUI
import CineLarkDomain

struct SearchView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Text(language.localized("nav.search"))
                    .font(.system(size: 44, weight: .bold))

                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(language.localized("search.prompt"), text: $query)
                        .textFieldStyle(.plain)
                        .font(.title2)
                        .focused($isSearchFocused)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(language.localized("general.dismiss"))
                    }
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: 720)
                .frame(height: 58)
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
            }
            .padding(.horizontal, CineLarkTheme.contentMargin)
            .padding(.top, 34)
            .padding(.bottom, 24)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CineLarkPageBackground())
        .navigationTitle(language.localized("nav.search"))
        .task {
            isSearchFocused = true
        }
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(350))
                await model.search(query)
            } catch {
                // A newer query cancelled this task.
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                language.localized("search.empty"),
                systemImage: "sparkles.tv",
                description: Text(language.localized("search.empty_description"))
            )
        } else if model.isSearching && model.searchResults.isEmpty {
            ProgressView(language.localized("search.searching"))
                .controlSize(.large)
        } else if model.searchResults.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            SearchResultGrid(items: model.searchResults)
        }
    }
}

private struct SearchResultGrid: View {
    let items: [MediaSummary]
    private let columns = [
        GridItem(.adaptive(minimum: 286, maximum: 380), spacing: 28, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                ForEach(items) { item in
                    SearchResultLink(item: item)
                }
            }
            .focusSection()
            .padding(.horizontal, CineLarkTheme.contentMargin)
            .padding(.vertical, 24)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SearchResultLink: View {
    @Environment(\.mediaTransitionNamespace) private var transitionNamespace
    let item: MediaSummary
    @State private var transitionID = UUID()
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(value: MediaDetailRoute(item: item, transitionID: transitionID)) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(url: item.backdropURL ?? item.posterURL)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .mediaMatchedGeometry(
                        id: transitionID,
                        namespace: transitionNamespace,
                        isSource: true
                    )

                LinearGradient(
                    colors: [.clear, .black.opacity(0.88)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let year = item.releaseYear { Text(String(year)) }
                        if let rating = item.rating {
                            Label(rating.cineLarkRating, systemImage: "star.fill")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(
                RoundedRectangle(cornerRadius: CineLarkTheme.cardRadius, style: .continuous)
            )
            .cineLarkCardLift(
                isActive: isFocused || isHovering,
                cornerRadius: CineLarkTheme.cardRadius,
                scale: 1.035
            )
        }
        .buttonStyle(CineLarkPressButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }
}
