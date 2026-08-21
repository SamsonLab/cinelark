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
                    .font(CineLarkDesign.Typography.pageTitle)

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
            .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
            .padding(.top, CineLarkDesign.Layout.pageTopInset)
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
            PosterGrid(items: model.searchResults)
        }
    }
}
