import SwiftUI
import CineLarkDomain

struct ContinueWatchingShelf: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Continue Watching")
                .font(.title2.bold())

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(model.continueWatching) { item in
                        Button {
                            Task { await model.play(item) }
                        } label: {
                            ContinueWatchingCard(
                                item: item,
                                isPlaying: model.playingItemID == item.id
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.playingItemID != nil)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                ArtworkView(url: item.thumbnailURL ?? item.posterURL)
                    .frame(width: 300, height: 169)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                Circle()
                    .fill(.black.opacity(0.68))
                    .frame(width: 54, height: 54)
                    .overlay {
                        if isPlaying {
                            ProgressView()
                        } else {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .offset(x: 2)
                        }
                    }
            }
            .overlay(alignment: .bottom) {
                ProgressView(value: item.userState.progress)
                    .progressViewStyle(.linear)
                    .tint(.cyan)
                    .padding(8)
            }

            Text(item.title)
                .font(.headline)
                .lineLimit(1)
                .frame(width: 300, alignment: .leading)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
