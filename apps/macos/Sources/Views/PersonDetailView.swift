import SwiftUI
import CineLarkDomain

struct PersonDetailView: View {
    @Environment(\.appLanguage) private var language
    @State private var model: PersonDetailModel

    init(person: PersonCredit, provider: any MediaLibraryProvider) {
        _model = State(
            initialValue: PersonDetailModel(credit: person, provider: provider)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            hero

            if model.isLoading && model.works.isEmpty {
                ProgressView(language.localized("person.loading"))
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.works.isEmpty {
                ContentUnavailableView(
                    language.localized("person.no_works"),
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text(language.localized("person.no_works_description"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(language.localized("person.works", String(model.workCount)))
                        .font(.title2.bold())
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                    MediaGrid(items: model.works)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            Button(language.localized("general.dismiss"), role: .cancel) { model.dismissError() }
        } message: {
            Text(language.userFacingError(model.errorMessage))
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
                Text(language.localized("person.cast_crew"))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(model.name)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                Text(
                    language.localized(
                        model.workCount == 1
                            ? "person.appears_one"
                            : "person.appears_many",
                        String(model.workCount)
                    )
                )
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
                            language.localized(
                                model.isFavorite
                                    ? "detail.favorite"
                                    : "detail.add_favorite"
                            ),
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
