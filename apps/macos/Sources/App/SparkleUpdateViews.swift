import Combine
import Sparkle
import SwiftUI

@MainActor
final class SparkleUpdateMonitor: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var availableVersion: String?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        availableVersion = nil
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        switch choice {
        case .skip, .install:
            availableVersion = nil
        case .dismiss:
            break
        @unknown default:
            break
        }
    }
}

@MainActor
private final class SparkleUpdateAvailability: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct SparkleMenuUpdateButton: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject private var availability: SparkleUpdateAvailability
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        availability = SparkleUpdateAvailability(updater: updater)
    }

    var body: some View {
        Button(language.localized("update.check"), action: updater.checkForUpdates)
            .disabled(!availability.canCheckForUpdates)
    }
}

struct SparkleUpdateOverlay: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject private var availability: SparkleUpdateAvailability
    private let updater: SPUUpdater
    private let availableVersion: String

    init(updater: SPUUpdater, availableVersion: String) {
        self.updater = updater
        self.availableVersion = availableVersion
        availability = SparkleUpdateAvailability(updater: updater)
    }

    var body: some View {
        Button(action: updater.checkForUpdates) {
            Label(
                language.localized("update.available", availableVersion),
                systemImage: "arrow.down.circle.fill"
            )
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize()
            .padding(.horizontal, 16)
            .frame(height: 38)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .disabled(!availability.canCheckForUpdates)
        .help(language.localized("update.check_help"))
        .accessibilityLabel(language.localized("update.available", availableVersion))
    }
}
