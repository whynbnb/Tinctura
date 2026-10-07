import SwiftUI
import AppKit
import ObjectiveC

// MARK: - Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return NSLocalizedString("跟随系统", comment: "")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    /// The localization actually used for bundle lookups.
    var resolvedCode: String {
        switch self {
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        }
    }

    var localeIdentifier: String { resolvedCode == "zh-Hans" ? "zh-Hans" : "en" }
}

/// Redirects `Bundle.main` string lookups to the selected language so that
/// SwiftUI's `Text("…")` keys resolve at runtime without a relaunch.
final class LanguageBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) static var language = "en"

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let path = Bundle.main.path(forResource: Self.language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

@MainActor
final class LanguageManager: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            apply(store: true)
        }
    }

    private static let defaultsKey = "settings.language"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        language = AppLanguage(rawValue: saved ?? "") ?? .system
        apply(store: false)
    }

    var localeIdentifier: String { language.localeIdentifier }

    private func apply(store: Bool) {
        LanguageBundle.language = language.resolvedCode
        object_setClass(Bundle.main, LanguageBundle.self)
        if store {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
        }
    }
}

// MARK: - Appearance

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return NSLocalizedString("跟随系统", comment: "")
        case .light: return NSLocalizedString("浅色", comment: "")
        case .dark: return NSLocalizedString("深色", comment: "")
        }
    }
}

@MainActor
final class AppearanceManager: ObservableObject {
    @Published var appearance: AppAppearance {
        didSet {
            guard appearance != oldValue else { return }
            apply(store: true)
        }
    }

    private static let defaultsKey = "settings.appearance"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        appearance = AppAppearance(rawValue: saved ?? "") ?? .system
        apply(store: false)
    }

    private func apply(store: Bool) {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        if store {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.defaultsKey)
        }
    }
}
