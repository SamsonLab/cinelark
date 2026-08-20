import SwiftUI
import CineLarkDomain

struct MediaCard: View {
    let item: MediaSummary

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
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

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
                .padding(.vertical, 4)
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
