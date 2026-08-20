import SwiftUI

struct SearchView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel
    @State private var query = ""

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    language.localized("search.empty"),
                    systemImage: "magnifyingglass",
                    description: Text(language.localized("search.empty_description"))
                )
            } else if model.isSearching && model.searchResults.isEmpty {
                ProgressView(language.localized("search.searching"))
                    .controlSize(.large)
            } else if model.searchResults.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                MediaGrid(items: model.searchResults)
            }
        }
        .navigationTitle(language.localized("nav.search"))
        .searchable(
            text: $query,
            placement: .toolbar,
            prompt: language.localized("search.prompt")
        )
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(350))
                await model.search(query)
            } catch {
                // A newer query cancelled this task.
            }
        }
    }
}
