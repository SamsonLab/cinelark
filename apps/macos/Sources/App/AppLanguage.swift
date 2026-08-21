import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case simplifiedChinese

    static let storageKey = "appLanguage"

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
            ? .simplifiedChinese
            : .english
    }

    var id: Self { self }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizedBundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    func displayName(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.english, .english): "English"
        case (.english, .simplifiedChinese): "Simplified Chinese"
        case (.simplifiedChinese, .english): "英语"
        case (.simplifiedChinese, .simplifiedChinese): "简体中文"
        }
    }

    func duration(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return localized("duration.hours_minutes", String(hours), String(minutes))
        }
        return localized("duration.minutes", String(minutes))
    }

    func playbackTimestamp(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    func progressPercent(_ progress: Double) -> String {
        let normalized = min(max(progress, 0), 1)
        let percentage = Int((normalized * 100).rounded())
        return "\(normalized > 0 ? max(percentage, 1) : 0)%"
    }

    func userFacingError(_ message: String?) -> String {
        guard let message, !message.isEmpty else {
            return localized("error.generic")
        }
        guard self == .simplifiedChinese else { return message }
        guard let key = Self.errorLocalizationKeys[message] else {
            return localized("error.generic")
        }
        return localized(key)
    }

    private var localeIdentifier: String {
        switch self {
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }

    private var localizedBundle: Bundle {
        guard let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    private static let errorLocalizationKeys: [String: String] = [
        "Please sign in to continue.": "error.unauthenticated",
        "The username, password, or TOTP code was not accepted.": "error.invalid_credentials",
        "Your session has expired. Please sign in again.": "error.session_expired",
        "This account cannot access the requested content.": "error.forbidden",
        "The requested content is no longer available.": "error.not_found",
        "Too many requests. Please try again shortly.": "error.rate_limited",
        "CineLark could not create a valid provider request.": "error.invalid_request",
        "The provider returned data CineLark could not understand.": "error.invalid_response",
        "The provider is currently unavailable.": "error.unavailable",
        "This provider capability is not supported yet.": "error.unsupported",
        "IINA is not installed. Install IINA to play this item.": "error.iina_missing",
        "CineLark could not open this item in IINA.": "error.iina_launch",
        "CineLark opened the IINA Bridge installer. Approve the installation, then play again.": "error.iina_plugin_install",
        "The CineLark IINA Bridge is not enabled. Enable it in IINA, then try again.": "error.iina_plugin_unavailable",
        "CineLark could not start its bundled playback helper.": "error.bridge_helper",
        "IINA could not authenticate with CineLark. Reinstall the bridge to pair it again.": "error.bridge_authentication",
        "The CineLark IINA Bridge is unavailable. Start IINA and try again.": "error.bridge_unavailable",
        "CineLark could not complete the request.": "error.generic",
        "CineLark could not load favorites.": "error.favorites",
        "CineLark could not load this person.": "error.person",
        "CineLark could not prepare this version.": "error.playback_options",
        "CineLark could not copy the link.": "error.copy_link",
        "CineLark could not open the download link.": "error.open_download"
    ]
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLanguage.systemDefault
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}

struct LanguageMenu: View {
    @Environment(\.appLanguage) private var language
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.systemDefault.rawValue

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { option in
                Button {
                    storedLanguage = option.rawValue
                } label: {
                    if option == language {
                        Label(language.displayName(for: option), systemImage: "checkmark")
                    } else {
                        Text(language.displayName(for: option))
                    }
                }
            }
        } label: {
            Label(language.localized("language.label"), systemImage: "globe")
        }
        .help(language.localized("language.help"))
    }
}
