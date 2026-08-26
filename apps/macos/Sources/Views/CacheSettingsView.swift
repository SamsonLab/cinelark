import ComposableArchitecture
import SwiftUI

struct CacheSettingsView: View {
    @Bindable var store: StoreOf<CacheFeature>

    var body: some View {
        Form {
            Section("Storage") {
                cacheRow("Media Metadata", bytes: store.usage.metadataBytes)
                cacheRow("Artwork", bytes: store.usage.artworkBytes)
                LabeledContent("Total") {
                    Text(formatted(store.usage.totalBytes))
                        .fontWeight(.semibold)
                }

                if store.isLoading {
                    ProgressView("Calculating cache size…")
                }
            }

            Section {
                Button("Clear Cache…", role: .destructive) {
                    store.send(.view(.clearButtonTapped))
                }
                .disabled(store.isClearing)

                if store.isClearing {
                    ProgressView("Clearing cache…")
                }
            } footer: {
                Text(
                    "Clearing removes recreatable media metadata and artwork. "
                    + "Profiles, favorites, playback progress, sources, credentials, and Remote pairings are preserved."
                )
            }

            if let failure = store.failure {
                Section("Error") {
                    Text(failure.message)
                        .foregroundStyle(.red)
                    Button("Try Again") {
                        store.send(.view(.refresh))
                    }
                }
            }
        }
        .formStyle(.grouped)
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
