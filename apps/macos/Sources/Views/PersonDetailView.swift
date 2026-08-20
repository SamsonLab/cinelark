import SwiftUI
import CineLarkDomain

struct PersonDetailView: View {
    @State private var model: PersonDetailModel

    init(person: PersonCredit, provider: any MediaLibraryProvider) {
        _model = State(
            initialValue: PersonDetailModel(credit: person, provider: provider)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            Divider()

            if model.isLoading && model.works.isEmpty {
                ProgressView("Loading works…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.works.isEmpty {
                ContentUnavailableView(
                    "No works available",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("The provider returned no linked titles.")
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Works  \(model.workCount)")
                        .font(.title2.bold())
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                    MediaGrid(items: model.works)
                }
            }
        }
        .background(Color.black.opacity(0.94))
        .navigationTitle(model.name)
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

    private var hero: some View {
        HStack(spacing: 32) {
            ArtworkView(
                url: model.avatarURL,
                placeholderSystemImage: "person.fill"
            )
            .frame(width: 220, height: 220)
            .clipShape(Circle())
            .overlay { Circle().stroke(Color.white.opacity(0.12)) }

            VStack(alignment: .leading, spacing: 16) {
                Text("CAST & CREW")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                Text(model.name)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                Text("Appears in \(model.workCount) title\(model.workCount == 1 ? "" : "s")")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await model.addToFavorites() }
                } label: {
                    if model.isUpdatingFavorite {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            model.isFavorite ? "Favorited" : "Add to Favorites",
                            systemImage: model.isFavorite ? "heart.fill" : "heart"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(model.isFavorite ? .orange : .accentColor)
                .disabled(model.isFavorite || model.isUpdatingFavorite || model.detail == nil)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(40)
    }
}
