import SwiftUI
import CineLarkDomain

struct HomeView: View {
    private enum HeroCandidate: Hashable {
        case continueItem(String)
        case media(String)
    }

    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel
    @State private var highlightedContinueID: String?
    @State private var highlightedMediaID: String?
    @State private var pendingHero: HeroCandidate?
    @State private var isHeroVisible = true
    @State private var viewportHeight: CGFloat = 900

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 44) {
                hero

                if !model.continueWatching.isEmpty {
                    ContinueWatchingShelf(model: model) { item in
                        queueHero(.continueItem(item.id))
                    }
                    .padding(.top, -118)
                }

                if model.isLoadingHome && model.hotItems.isEmpty {
                    ProgressView(language.localized("home.loading"))
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }

                if !model.hotItems.isEmpty {
                    MediaShelf(
                        title: language.localized("home.popular_now"),
                        items: model.hotItems,
                        onHighlight: highlight
                    )
                }

                ForEach(model.collections) { collection in
                    let items = model.items(in: collection, sort: .newest)
                    if !items.isEmpty {
                        MediaShelf(
                            title: collection.name,
                            items: items,
                            viewAllCollection: collection
                        )
                    }
                }
            }
            .padding(.bottom, 64)
        }
        .scrollIndicators(.hidden)
        .background(CineLarkPageBackground())
        .navigationTitle(language.localized("nav.home"))
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { height in
            viewportHeight = height
        }
        .task(id: pendingHero) {
            guard isHeroVisible, let pendingHero else { return }
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            switch pendingHero {
            case .continueItem(let id):
                highlightedContinueID = id
                highlightedMediaID = nil
            case .media(let id):
                highlightedMediaID = id
                highlightedContinueID = nil
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            CineLarkCinematicBackdrop(
                url: featuredSummary?.backdropURL ?? featuredSummary?.posterURL,
                height: heroHeight,
                leadingShade: 0.88
            )
            .id(featuredSummary?.id)
            .transition(.opacity)

            VStack(alignment: .leading, spacing: 18) {
                if let featuredSummary {
                    Text(
                        language.localized(
                            featuredSummary.kind == .movie ? "detail.movie" : "detail.series"
                        )
                    )
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                    Text(featuredSummary.title)
                        .font(.system(size: 58, weight: .bold))
                        .lineLimit(2)
                        .frame(maxWidth: 720, alignment: .leading)

                    metadata(for: featuredSummary)

                    if let synopsis = featuredSummary.synopsis, !synopsis.isEmpty {
                        Text(synopsis)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(3)
                            .frame(maxWidth: 680, alignment: .leading)
                    }

                    heroActions(for: featuredSummary)
                } else if model.isLoadingHome {
                    ProgressView(language.localized("home.loading"))
                        .controlSize(.large)
                } else {
                    Text("CineLark")
                        .font(.system(size: 58, weight: .bold))
                }
            }
            .padding(.horizontal, CineLarkTheme.contentMargin)
            .padding(.bottom, model.continueWatching.isEmpty ? 64 : 170)
            .animation(CineLarkTheme.heroAnimation, value: featuredSummary?.id)

        }
        .frame(height: heroHeight)
        .onScrollVisibilityChange(threshold: 0.25) { isVisible in
            isHeroVisible = isVisible
            if !isVisible {
                pendingHero = nil
            }
        }
    }

    private var heroHeight: CGFloat {
        min(690, max(540, viewportHeight * 0.82))
    }

    @ViewBuilder
    private func metadata(for item: MediaSummary) -> some View {
        HStack(spacing: 12) {
            if let year = item.releaseYear {
                Text(String(year))
            }
            if let rating = item.rating {
                Label(rating.cineLarkRating, systemImage: "star.fill")
            }
            if let duration = item.durationSeconds {
                Text(language.duration(duration))
            }
            if let seasons = item.totalSeasons {
                Text(
                    language.localized(
                        seasons == 1 ? "detail.season_count_one" : "detail.season_count_many",
                        String(seasons)
                    )
                )
            }
        }
        .font(.callout.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func heroActions(for item: MediaSummary) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if let featuredContinue {
                    Button {
                        Task { await model.play(featuredContinue) }
                    } label: {
                        Label(
                            language.localized(
                                "detail.continue",
                                language.progressPercent(featuredContinue.userState.progress)
                            ),
                            systemImage: "play.fill"
                        )
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                    .disabled(model.playingItemID != nil)
                }

                if let featuredContinue {
                    NavigationLink(value: featuredContinue.mediaSummary) {
                        Label(language.localized("home.open_details"), systemImage: "info.circle")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.extraLarge)
                } else {
                    NavigationLink(value: item) {
                        Label(language.localized("home.open_details"), systemImage: "info.circle")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                }
            }
        }
    }

    private var featuredContinue: ContinueWatchingItem? {
        if let highlightedContinueID,
           let highlighted = model.continueWatching.first(where: { $0.id == highlightedContinueID }) {
            return highlighted
        }
        guard highlightedMediaID == nil else { return nil }
        return model.continueWatching.first
    }

    private var featuredSummary: MediaSummary? {
        if let featuredContinue {
            return knownItems.first(where: { $0.id == featuredContinue.mediaSummary.id })
                ?? featuredContinue.mediaSummary
        }
        if let highlightedMediaID,
           let highlighted = knownItems.first(where: { $0.id == highlightedMediaID }) {
            return highlighted
        }
        return model.hotItems.first
    }

    private var knownItems: [MediaSummary] {
        var seen: Set<String> = []
        let collectionItems = model.collections.flatMap {
            model.items(in: $0, sort: .newest)
        }
        return (model.hotItems + collectionItems).filter { seen.insert($0.id).inserted }
    }

    private func highlight(_ item: MediaSummary) {
        queueHero(.media(item.id))
    }

    private func queueHero(_ candidate: HeroCandidate) {
        guard isHeroVisible else { return }
        pendingHero = candidate
    }
}
