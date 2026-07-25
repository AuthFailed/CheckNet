import Foundation

/// Guesses a country flag emoji from a server remark (e.g. "Швеция", "US · YT",
/// "Netherlands | Reserve"). Node remarks rarely carry a machine-readable code,
/// so we match known country names (RU + EN) and ISO codes.
public enum CountryFlag {
    /// Flag emoji for a remark, or nil when no country is recognised.
    public static func emoji(for remark: String) -> String? {
        let upper = " " + remark.uppercased()
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "·", with: " ") + " "
        // Longer names first so "United States" wins before a stray "US".
        for (needle, iso) in table {
            if upper.contains(needle) { return flag(iso) }
        }
        return nil
    }

    /// Split a remark into a flag and a display title. If the remark already
    /// starts with a flag emoji (e.g. "🇩🇪 DE Senko"), reuse it and drop it from
    /// the title; otherwise derive the flag from the country name/code.
    public static func split(_ remark: String) -> (flag: String, title: String) {
        let trimmed = remark.trimmingCharacters(in: .whitespaces)
        if let lead = leadingFlag(trimmed) {
            let rest = String(trimmed.dropFirst(lead.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " |·-—"))
            return (lead, rest.isEmpty ? trimmed : rest)
        }
        return (emoji(for: remark) ?? "🌐", remark)
    }

    /// The leading flag emoji (a pair of regional-indicator scalars), if any.
    static func leadingFlag(_ s: String) -> String? {
        let scalars = Array(s.unicodeScalars)
        guard scalars.count >= 2,
              (0x1F1E6...0x1F1FF).contains(scalars[0].value),
              (0x1F1E6...0x1F1FF).contains(scalars[1].value) else { return nil }
        return String(String.UnicodeScalarView(scalars[0...1]))
    }

    /// ISO region code (e.g. "DE") from a flag emoji, or nil if it isn't one.
    public static func iso(fromFlag flag: String) -> String? {
        let scalars = Array(flag.unicodeScalars)
        guard scalars.count == 2 else { return nil }
        var iso = ""
        for s in scalars {
            guard (0x1F1E6...0x1F1FF).contains(s.value),
                  let u = UnicodeScalar(s.value - 0x1F1E6 + 65) else { return nil }
            iso.unicodeScalars.append(u)
        }
        return iso
    }

    /// A flag with its country name for display: "🇩🇪" → "🇩🇪 Германия"
    /// (localized to `locale`). Falls back to the bare flag if unknown.
    public static func label(forFlag flag: String, locale: Locale = .current) -> String {
        guard let iso = iso(fromFlag: flag),
              let name = locale.localizedString(forRegionCode: iso) else { return flag }
        return "\(flag) \(name)"
    }

    /// Two-letter ISO code → regional-indicator flag emoji.
    public static func flag(_ iso: String) -> String {
        let base: UInt32 = 0x1F1E6
        var s = ""
        for scalar in iso.uppercased().unicodeScalars where scalar.value >= 65 && scalar.value <= 90 {
            if let u = UnicodeScalar(base + (scalar.value - 65)) { s.unicodeScalars.append(u) }
        }
        return s.isEmpty ? "🏳️" : s
    }

    // Ordered: multi-word / specific names before short codes. Each key is padded
    // to whole words at the call site via surrounding spaces.
    private static let table: [(String, String)] = [
        ("ВЕЛИКОБРИТАНИЯ", "GB"), ("UNITED KINGDOM", "GB"), ("БРИТАНИЯ", "GB"), ("ENGLAND", "GB"), ("ЛОНДОН", "GB"),
        ("UNITED STATES", "US"), ("АМЕРИКА", "US"), ("США", "US"),
        ("НИДЕРЛАНДЫ", "NL"), ("NETHERLANDS", "NL"), ("ГОЛЛАНДИЯ", "NL"), ("АМСТЕРДАМ", "NL"),
        ("ГЕРМАНИЯ", "DE"), ("GERMANY", "DE"), ("ФРАНКФУРТ", "DE"),
        ("ФРАНЦИЯ", "FR"), ("FRANCE", "FR"), ("ПАРИЖ", "FR"),
        ("ШВЕЦИЯ", "SE"), ("SWEDEN", "SE"), ("СТОКГОЛЬМ", "SE"),
        ("ФИНЛЯНДИЯ", "FI"), ("FINLAND", "FI"), ("ХЕЛЬСИНКИ", "FI"),
        ("ПОЛЬША", "PL"), ("POLAND", "PL"), ("ВАРШАВА", "PL"),
        ("ЛИТВА", "LT"), ("LITHUANIA", "LT"),
        ("ЛАТВИЯ", "LV"), ("LATVIA", "LV"),
        ("ЭСТОНИЯ", "EE"), ("ESTONIA", "EE"),
        ("КАЗАХСТАН", "KZ"), ("KAZAKHSTAN", "KZ"),
        ("АВСТРИЯ", "AT"), ("AUSTRIA", "AT"),
        ("ШВЕЙЦАРИЯ", "CH"), ("SWITZERLAND", "CH"),
        ("ИСПАНИЯ", "ES"), ("SPAIN", "ES"),
        ("ИТАЛИЯ", "IT"), ("ITALY", "IT"),
        ("НОРВЕГИЯ", "NO"), ("NORWAY", "NO"),
        ("ДАНИЯ", "DK"), ("DENMARK", "DK"),
        ("ТУРЦИЯ", "TR"), ("TURKEY", "TR"), ("СТАМБУЛ", "TR"),
        ("ЯПОНИЯ", "JP"), ("JAPAN", "JP"), ("ТОКИО", "JP"),
        ("СИНГАПУР", "SG"), ("SINGAPORE", "SG"),
        ("ГОНКОНГ", "HK"), ("HONG KONG", "HK"),
        ("КОРЕЯ", "KR"), ("KOREA", "KR"),
        ("ИНДИЯ", "IN"), ("INDIA", "IN"),
        ("КАНАДА", "CA"), ("CANADA", "CA"),
        ("БРАЗИЛИЯ", "BR"), ("BRAZIL", "BR"),
        ("ОАЭ", "AE"), ("ЭМИРАТЫ", "AE"), ("DUBAI", "AE"), ("ДУБАЙ", "AE"),
        ("РОССИЯ", "RU"), ("RUSSIA", "RU"), ("МОСКВА", "RU"),
        ("УКРАИНА", "UA"), ("UKRAINE", "UA"),
        ("БЕЛАРУСЬ", "BY"), ("BELARUS", "BY"),
        ("ЧЕХИЯ", "CZ"), ("CZECH", "CZ"),
        ("РУМЫНИЯ", "RO"), ("ROMANIA", "RO"),
        ("БОЛГАРИЯ", "BG"), ("BULGARIA", "BG"),
        ("ИРЛАНДИЯ", "IE"), ("IRELAND", "IE"),
        ("АРМЕНИЯ", "AM"), ("ARMENIA", "AM"),
        ("ГРУЗИЯ", "GE"), ("GEORGIA", "GE"),
        // Short ISO/EN codes last (space-padded to avoid substring hits).
        (" UK ", "GB"), (" USA ", "US"), (" US ", "US"), (" NL ", "NL"), (" DE ", "DE"),
        (" FR ", "FR"), (" SE ", "SE"), (" FI ", "FI"), (" PL ", "PL"), (" JP ", "JP"),
        (" SG ", "SG"), (" TR ", "TR"), (" KZ ", "KZ"), (" AT ", "AT"), (" NO ", "NO"),
    ]
}
