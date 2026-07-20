import Foundation
import ObjectiveC

/// Enables true in-app language switching without a relaunch.
///
/// SwiftUI's `.environment(\.locale)` changes formatting but does **not**
/// reliably re-resolve `Text`/`LocalizedStringKey` lookups against the chosen
/// language — runtime-built keys (tool descriptions, engine strings) keep
/// falling back to the development language (Russian). We fix that at the
/// Foundation level: swap `Bundle.main` for a subclass whose
/// `localizedString(forKey:value:table:)` routes to the selected language's
/// `.lproj` bundle (compiled from `Localizable.xcstrings`). Every `Text`
/// ultimately resolves through this, so the whole UI switches at once.
private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let override = objc_getAssociatedObject(self, &LanguageBundle.key) as? Bundle {
            return override.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
    nonisolated(unsafe) static var key: UInt8 = 0
}

enum AppLocalization {
    private static let install: Void = {
        object_setClass(Bundle.main, LanguageBundle.self)
    }()

    /// Point `Bundle.main` at the given language code's `.lproj` (nil = follow
    /// the system). Codes must match the catalog / `CFBundleLocalizations`
    /// entries, e.g. "en", "ru", "zh-Hans", "pt-BR".
    static func apply(_ code: String?) {
        _ = install
        var override: Bundle?
        if let code {
            let candidates = [code, code.replacingOccurrences(of: "-", with: "_")]
            if let path = candidates.lazy
                .compactMap({ Bundle.main.path(forResource: $0, ofType: "lproj") })
                .first {
                override = Bundle(path: path)
            }
        }
        objc_setAssociatedObject(Bundle.main, &LanguageBundle.key, override,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
