import Charts
import ComposableArchitecture
import SwiftUI
import CineLarkDomain
import CineLarkInsights

struct InsightsView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var store: StoreOf<InsightsFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if let snapshot = store.snapshot {
                    if snapshot.sessionCount == 0 {
                        emptyState
                    } else {
                        summary(snapshot)
                        activity(snapshot)
                        topTitles(snapshot.topTitles)
                        affinities(snapshot)
                    }
                } else if store.isLoading {
                    ProgressView(language.localized("insights.loading"))
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let failure = store.failure {
                    ContentUnavailableView {
                        Label(
                            language.localized("insights.unavailable"),
                            systemImage: "chart.bar.xaxis"
                        )
                    } description: {
                        Text(failure.message)
                    } actions: {
                        Button(language.localized("general.refresh")) {
                            store.send(.view(.reload))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(.horizontal, CineLarkDesign.Layout.contentMargin)
            .padding(.top, CineLarkDesign.Layout.pageTopInset)
            .padding(.bottom, 60)
            .frame(maxWidth: 1280, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task {
            store.send(.view(.appeared))
        }
        .onDisappear {
            store.send(.view(.disappeared))
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(language.localized("insights.title"))
                    .font(CineLarkDesign.Typography.pageTitle)
                Text(language.localized("insights.subtitle"))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            Picker(
                language.localized("insights.period"),
                selection: Binding(
                    get: { store.selectedPeriod },
                    set: { store.send(.view(.periodSelected($0))) }
                )
            ) {
                ForEach(ViewingInsightPeriod.allCases, id: \.self) { period in
                    Text(periodTitle(period)).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 390)
        }
    }

    private func summary(_ snapshot: ViewingInsightsSnapshot) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 14)],
            spacing: 14
        ) {
            metricCard(
                language.localized("insights.watch_time"),
                value: language.duration(snapshot.totalWatchSeconds),
                symbol: "clock.fill"
            )
            metricCard(
                language.localized("insights.sessions"),
                value: String(snapshot.sessionCount),
                symbol: "play.rectangle.on.rectangle.fill"
            )
            metricCard(
                language.localized("insights.completed"),
                value: String(snapshot.completedSessionCount),
                symbol: "checkmark.circle.fill"
            )
            metricCard(
                language.localized("insights.titles"),
                value: String(snapshot.distinctTitleCount),
                symbol: "film.stack.fill"
            )
            metricCard(
                language.localized("insights.active_days"),
                value: String(snapshot.activeDayCount),
                symbol: "calendar"
            )
            metricCard(
                language.localized("insights.longest_streak"),
                value: language.localized(
                    "insights.days_value",
                    String(snapshot.longestStreakDays)
                ),
                symbol: "flame.fill"
            )
        }
    }

    private func metricCard(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func activity(_ snapshot: ViewingInsightsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.localized("insights.activity"))
                .font(CineLarkDesign.Typography.sectionTitle)

            Chart(snapshot.activity) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Hours", point.watchedSeconds / 3_600)
                )
                .foregroundStyle(Color.blue.gradient)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)
            .padding(18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel(language.localized("insights.activity"))
        }
    }

    @ViewBuilder
    private func topTitles(_ titles: [ViewingInsightTitle]) -> some View {
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(language.localized("insights.top_titles"))
                    .font(CineLarkDesign.Typography.sectionTitle)

                VStack(spacing: 0) {
                    ForEach(Array(titles.prefix(10).enumerated()), id: \.element.id) { index, title in
                        HStack(spacing: 16) {
                            Text(String(index + 1))
                                .font(.title3.monospacedDigit().weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .trailing)
                            ArtworkView(
                                url: title.artworkURL,
                                placeholderSystemImage: placeholderSystemImage(for: title.kind),
                                locator: title.locator
                            )
                                .frame(width: 46, height: 69)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title.title)
                                    .font(.headline)
                                Text(language.localized(
                                    "insights.session_count",
                                    String(title.sessionCount)
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(language.duration(title.watchedSeconds))
                                .font(.headline.monospacedDigit())
                        }
                        .padding(.vertical, 10)

                        if index < titles.prefix(10).count - 1 {
                            Divider().padding(.leading, 92)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func placeholderSystemImage(for kind: MediaKind?) -> String {
        guard let kind else { return "film" }
        return switch kind {
        case .movie: "film"
        case .series: "tv"
        case .episode: "play.rectangle"
        }
    }

    @ViewBuilder
    private func affinities(_ snapshot: ViewingInsightsSnapshot) -> some View {
        let dimensions = [
            (language.localized("insights.genres"), snapshot.topGenres),
            (language.localized("insights.directors"), snapshot.topDirectors),
            (language.localized("insights.actors"), snapshot.topActors)
        ].filter { !$0.1.isEmpty }

        if !dimensions.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                ForEach(dimensions, id: \.0) { title, entries in
                    dimensionCard(title: title, entries: entries)
                }
            }
        } else {
            Label(
                language.localized("insights.metadata_empty"),
                systemImage: "sparkles"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func dimensionCard(
        title: String,
        entries: [ViewingInsightDimension]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))

            ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 10) {
                    Text(String(index + 1))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    Text(entry.name)
                        .lineLimit(1)
                    Spacer()
                    Text(language.duration(entry.watchedSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            language.localized("insights.empty"),
            systemImage: "chart.bar.xaxis",
            description: Text(language.localized("insights.empty_description"))
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func periodTitle(_ period: ViewingInsightPeriod) -> String {
        switch period {
        case .month: language.localized("insights.period.month")
        case .quarter: language.localized("insights.period.quarter")
        case .year: language.localized("insights.period.year")
        case .allTime: language.localized("insights.period.all_time")
        }
    }
}
