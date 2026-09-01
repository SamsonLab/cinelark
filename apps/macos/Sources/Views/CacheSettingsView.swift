import ComposableArchitecture
import SwiftUI

struct CacheSettingsView: View {
    @Bindable var store: StoreOf<CacheFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CineLarkSettingsPageHeader(
                    title: "Storage",
                    subtitle: "Review and clear recreatable local media data.",
                    systemImage: "internaldrive"
                )

                CineLarkSettingsCard(
                    "Cache Usage",
                    subtitle: "Profile, favorites, progress, and credentials are not included.",
                    systemImage: "chart.pie"
                ) {
                    cacheRow("Media Metadata", bytes: store.usage.metadataBytes)
                    Divider()
                    cacheRow("Artwork", bytes: store.usage.artworkBytes)
                    Divider()
                    LabeledContent("Total") {
                        Text(formatted(store.usage.totalBytes))
                            .fontWeight(.semibold)
                    }

                    if store.isLoading {
                        ProgressView("Calculating cache size…")
                    }
                }

                CineLarkSettingsCard(
                    "Clear Cache",
                    subtitle: "Media metadata and artwork download again when needed.",
                    systemImage: "trash"
                ) {
                    Button("Clear Cache…", role: .destructive) {
                        store.send(.view(.clearButtonTapped))
                    }
                    .buttonStyle(.glass)
                    .disabled(store.isClearing)

                    if store.isClearing {
                        ProgressView("Clearing cache…")
                    }

                    Text(
                        "The Personal Profile, favorites, playback progress, sources, "
                            + "credentials, and Remote pairings are preserved."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let failure = store.failure {
                    CineLarkSettingsCard(
                        "Storage Error",
                        systemImage: "exclamationmark.triangle"
                    ) {
                        Text(failure.message)
                            .foregroundStyle(.red)
                        Button("Try Again") {
                            store.send(.view(.refresh))
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .padding(28)
        }
        .background(CineLarkPageBackground())
        .task { store.send(.view(.appeared)) }
        .alert(
            "Clear all cached data?",
            isPresented: Binding(
                get: { store.showsClearConfirmation },
                set: { if !$0 { store.send(.view(.clearCancelled)) } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                store.send(.view(.clearCancelled))
            }
            Button("Clear Cache", role: .destructive) {
                store.send(.view(.clearConfirmed))
            }
        } message: {
            Text("Media metadata and artwork will be downloaded again when needed.")
        }
    }

    private func cacheRow(_ title: String, bytes: UInt64) -> some View {
        LabeledContent(title) {
            Text(formatted(bytes))
                .foregroundStyle(.secondary)
        }
    }

    private func formatted(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .file
        )
    }
}
