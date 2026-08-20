import SwiftUI

struct HomeView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Home")
                            .font(.largeTitle.bold())
                        Text("Continue watching or find something new.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.refreshHome() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoadingHome)
                }

                if model.isLoadingHome && model.hotItems.isEmpty {
                    ProgressView("Loading your library…")
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }

                if !model.continueWatching.isEmpty {
                    ContinueWatchingShelf(model: model)
                }

                if !model.hotItems.isEmpty {
                    MediaShelf(title: "Popular Now", items: model.hotItems)
                }

                if !model.collections.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Collections")
                            .font(.title2.bold())
                        Text("Choose a collection from the sidebar to browse its full library.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(36)
        }
        .background(Color.black.opacity(0.92))
        .navigationTitle("Home")
    }
}
