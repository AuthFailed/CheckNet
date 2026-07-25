import XCTest
@testable import NetworkKit

final class CountryFlagTests: XCTestCase {
    func testFlagFromISO() {
        XCTAssertEqual(CountryFlag.flag("US"), "🇺🇸")
        XCTAssertEqual(CountryFlag.flag("se"), "🇸🇪")
    }

    func testEmojiFromRussianRemark() {
        XCTAssertEqual(CountryFlag.emoji(for: "Швеция"), CountryFlag.flag("SE"))
        XCTAssertEqual(CountryFlag.emoji(for: "США"), CountryFlag.flag("US"))
        XCTAssertEqual(CountryFlag.emoji(for: "Казахстан"), CountryFlag.flag("KZ"))
        XCTAssertEqual(CountryFlag.emoji(for: "Нидерланды | Резерв"), CountryFlag.flag("NL"))
        XCTAssertEqual(CountryFlag.emoji(for: "Великобритания | 📺 YT без рекламы"), CountryFlag.flag("GB"))
    }

    func testEmojiFromEnglishAndCodes() {
        XCTAssertEqual(CountryFlag.emoji(for: "Netherlands - Reserve"), CountryFlag.flag("NL"))
        XCTAssertEqual(CountryFlag.emoji(for: "US · YT"), CountryFlag.flag("US"))
        XCTAssertEqual(CountryFlag.emoji(for: "Germany"), CountryFlag.flag("DE"))
    }

    func testUnknownRemarkReturnsNil() {
        XCTAssertNil(CountryFlag.emoji(for: "АВТО ОБХОД"))
        XCTAssertNil(CountryFlag.emoji(for: "proxy-1"))
    }

    func testSplitUsesEmbeddedFlag() {
        // Remarks that already carry a flag must not get a second one.
        let (flag, title) = CountryFlag.split("🇩🇪 DE Senko  209d")
        XCTAssertEqual(flag, "🇩🇪")
        XCTAssertEqual(title, "DE Senko  209d")
    }

    func testSplitDerivesFlagWhenAbsent() {
        let (flag, title) = CountryFlag.split("Швеция")
        XCTAssertEqual(flag, CountryFlag.flag("SE"))
        XCTAssertEqual(title, "Швеция")
    }

    func testISOFromFlag() {
        XCTAssertEqual(CountryFlag.iso(fromFlag: "🇩🇪"), "DE")
        XCTAssertEqual(CountryFlag.iso(fromFlag: "🇺🇸"), "US")
        XCTAssertNil(CountryFlag.iso(fromFlag: "🌐"))
        XCTAssertNil(CountryFlag.iso(fromFlag: "abc"))
    }

    func testFlagLabelAppendsCountryName() {
        let ru = Locale(identifier: "ru_RU")
        XCTAssertEqual(CountryFlag.label(forFlag: "🇩🇪", locale: ru), "🇩🇪 Германия")
        XCTAssertTrue(CountryFlag.label(forFlag: "🇺🇸", locale: ru).hasPrefix("🇺🇸 Соедин"))
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(CountryFlag.label(forFlag: "🇩🇪", locale: en), "🇩🇪 Germany")
        // Unknown flag falls back to itself.
        XCTAssertEqual(CountryFlag.label(forFlag: "🌐", locale: ru), "🌐")
    }

    func testSplitFallsBackToGlobe() {
        let (flag, title) = CountryFlag.split("proxy")
        XCTAssertEqual(flag, "🌐")
        XCTAssertEqual(title, "proxy")
    }

    func testAutoUAOrderStartsPopular() {
        XCTAssertEqual(SubscriptionUserAgents.autoOrder.first, "v2rayNG/1.9.5")
        XCTAssertFalse(SubscriptionUserAgents.autoOrder.contains { $0.isEmpty })
        XCTAssertEqual(SubscriptionUserAgents.all.first?.id, "auto")
    }
}
