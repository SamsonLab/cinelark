import SwiftUI
import CineLarkDomain

struct MediaCard: View {
    let item: MediaSummary
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArtworkView(url: item.posterURL)
                .frame(width: 178, height: 267)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(alignment: .bottom) {
                    if item.userState.progress > 0 && !item.userState.played {
                        ProgressView(value: item.userState.progress)
                            .progressViewStyle(.linear)
                            .tint(.cyan)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if item.userState.favorite == true {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.orange)
                            .padding(9)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(
                            isHovering
                                ? Color.accentColor.opacity(0.7)
                                : Color.white.opacity(0.08),
                            lineWidth: isHovering ? 1.5 : 1
                        )
                }
                .shadow(
                    color: .black.opacity(isHovering ? 0.55 : 0.35),
                    radius: isHovering ? 18 : 12,
                    y: isHovering ? 9 : 6
                )

            Text(item.title)
                .font(.headline)
                .lineLimit(1)
                .frame(width: 178, alignment: .leading)

            HStack(spacing: 8) {
                if let year = item.releaseYear {
                    Text(String(year))
                }
                if let rating = item.rating {
                    Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.025 : 1)
        .offset(y: isHovering ? -3 : 0)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovering)
    }
}

struct MediaShelf: View {
    let title: String
    let items: [MediaSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 22) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            MediaCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct MediaGrid: View {
    let items: [MediaSummary]

    private let columns = [
        GridItem(.adaptive(minimum: 178, maximum: 210), spacing: 28, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 32) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        MediaCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(32)
        }
        .background(Color.black.opacity(0.92))
    }
}
