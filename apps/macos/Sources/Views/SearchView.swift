import SwiftUI

struct SearchView: View {
    @Bindable var model: AppModel
    @State private var query = ""

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Search your library",
                    systemImage: "magnifyingglass",
                    description: Text("Find movies and TV series by title.")
                )
            } else if model.isSearching && model.searchResults.isEmpty {
                ProgressView("Searching…")
                    .controlSize(.large)
            } else if model.searchResults.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                MediaGrid(items: model.searchResults)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .toolbar, prompt: "Movies and TV")
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
