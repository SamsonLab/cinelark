import ComposableArchitecture
import SwiftUI

struct CatalogPersonDetailView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var store: StoreOf<PersonDetailFeature>

    var body: some View {
        VStack(spacing: 0) {
            hero

            if store.isLoading && store.works.isEmpty {
                ProgressView(language.localized("person.loading"))
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.works.isEmpty {
                ContentUnavailableView(
                    language.localized("person.no_works"),
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text(language.localized("person.no_works_description"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(language.localized("person.works", String(store.works.count)))
                        .font(.title2.bold())
                        .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
                        .padding(.top, 24)
                    PosterGrid(items: store.works, navigationLevel: .route)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CineLarkPageBackground())
        .navigationTitle(name)
        .task { store.send(.view(.appeared)) }
    }

    private var hero: some View {
        HStack(spacing: 32) {
            ArtworkView(
                url: avatarURL,
                placeholderSystemImage: "person.fill",
                locator: .init(
                    sourceID: store.sourceID,
                    providerItemID: store.initialPerson.id
                )
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

                Text(name)
                    .font(.system(size: 48, weight: .bold))

                Text(language.localized(
                    store.works.count == 1 ? "person.appears_one" : "person.appears_many",
                    String(store.works.count)
                ))
                .font(.title3)
                .foregroundStyle(.secondary)

                if let failure = store.failure {
                    Label(
                        language.userFacingError(String(describing: failure)),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CineLarkDesign.Layout.contentMargin)
        .background {
            RadialGradient(
                colors: [Color.blue.opacity(0.16), .clear],
                center: .leading,
                startRadius: 20,
                endRadius: 560
            )
        }
    }

    private var name: String {
        store.detail?.name ?? store.initialPerson.name
    }

    private var avatarURL: URL? {
        store.detail?.avatarURL ?? store.initialPerson.avatarURL
    }
}
