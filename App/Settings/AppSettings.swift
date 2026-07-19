import SwiftUI
import Observation

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system, ru, en
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Системный"
        case .ru: return "Русский"
        case .en: return "English"
        }
    }
    /// Locale code applied to the app (nil = follow system).
    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .ru: return "ru"
        case .en: return "en"
        }
    }
}

/// App-wide preferences persisted to UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "checknet.theme") }
    }
    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "checknet.language") }
    }
    /// Drive Live Activities / Dynamic Island from ping runs.
    var liveActivitiesEnabled: Bool {
        didSet { UserDefaults.standard.set(liveActivitiesEnabled, forKey: "checknet.liveActivities") }
    }
    /// Resolve reverse-DNS names by default in tools that support it.
    var reverseDNSByDefault: Bool {
        didSet { UserDefaults.standard.set(reverseDNSByDefault, forKey: "checknet.rdnsDefault") }
    }

    init() {
        let d = UserDefaults.standard
        theme = AppTheme(rawValue: d.string(forKey: "checknet.theme") ?? "") ?? .system
        language = AppLanguage(rawValue: d.string(forKey: "checknet.language") ?? "") ?? .system
        liveActivitiesEnabled = d.object(forKey: "checknet.liveActivities") as? Bool ?? true
        reverseDNSByDefault = d.object(forKey: "checknet.rdnsDefault") as? Bool ?? true
    }
}
