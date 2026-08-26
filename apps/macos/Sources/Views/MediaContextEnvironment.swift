import SwiftUI
import CineLarkPluginAPI
import CineLarkProfile

private struct ActiveMediaSourceIDKey: EnvironmentKey {
    static let defaultValue: SourceID? = nil
}

private struct ActiveProfileIDKey: EnvironmentKey {
    static let defaultValue: ProfileID? = nil
}

extension EnvironmentValues {
    var activeMediaSourceID: SourceID? {
        get { self[ActiveMediaSourceIDKey.self] }
        set { self[ActiveMediaSourceIDKey.self] = newValue }
    }

    var activeProfileID: ProfileID? {
        get { self[ActiveProfileIDKey.self] }
        set { self[ActiveProfileIDKey.self] = newValue }
    }
}
