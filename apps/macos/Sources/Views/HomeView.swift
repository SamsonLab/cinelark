import SwiftUI

struct HomeView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.localized("nav.home"))
                            .font(.largeTitle.bold())
                        Text(language.localized("home.subtitle"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.refreshHome() }
                    } label: {
                        Label(language.localized("general.refresh"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoadingHome)
                }

                if model.isLoadingHome && model.hotItems.isEmpty {
                    ProgressView(language.localized("home.loading"))
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }

                if !model.continueWatching.isEmpty {
                    ContinueWatchingShelf(model: model)
                }

                if !model.hotItems.isEmpty {
                    MediaShelf(
                        title: language.localized("home.popular_now"),
                        items: model.hotItems
                    )
                }

                if !model.collections.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(language.localized("nav.collections"))
                            .font(.title2.bold())
                        Text(language.localized("home.collection_help"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(36)
        }
        .background(Color.black.opacity(0.92))
        .navigationTitle(language.localized("nav.home"))
    }
}
