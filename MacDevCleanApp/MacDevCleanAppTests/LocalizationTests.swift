import Domain
import XCTest

@testable import MacDevClean

@MainActor
final class LocalizationTests: XCTestCase {
    func testByteLabelDoesNotTurnUnknownIntoZero() {
        let english = LocalizedFormatters.bytes(nil, locale: Locale(identifier: "en"))
        let portuguese = LocalizedFormatters.bytes(nil, locale: Locale(identifier: "pt_BR"))

        XCTAssertEqual(english, "Unavailable")
        XCTAssertEqual(portuguese, "Indisponível")
    }

    func testAnUnknownSizeIsAnnouncedAsUnmeasuredRatherThanAsUnavailable() {
        // "Unavailable" is readable beside a visible label. On its own, which
        // is how VoiceOver reads it, it does not say what is unavailable.
        let english = LocalizedFormatters.accessibleBytes(
            nil, locale: Locale(identifier: "en"))
        let portuguese = LocalizedFormatters.accessibleBytes(
            nil, locale: Locale(identifier: "pt_BR"))

        XCTAssertEqual(english, "Size could not be measured")
        XCTAssertEqual(portuguese, "Não foi possível medir o tamanho")
        XCTAssertEqual(
            LocalizedFormatters.accessibleBytes(1_500_000, locale: Locale(identifier: "en_US")),
            "1.5 MB",
            "a measured size is announced exactly as it is shown")
    }

    func testFormattersUseTheRequestedLocaleForBytesAndDates() {
        XCTAssertEqual(
            LocalizedFormatters.bytes(1_500_000, locale: Locale(identifier: "en_US")),
            "1.5 MB"
        )
        XCTAssertEqual(
            LocalizedFormatters.bytes(1_500_000, locale: Locale(identifier: "pt_BR")),
            "1,5 MB"
        )

        // Pinned to UTC: the same instant is a different day either side of
        // midnight, so a host-zone expectation would pass or fail by location.
        let utc = TimeZone(identifier: "UTC")!
        let newYear = Date(timeIntervalSince1970: 946_684_800)
        XCTAssertEqual(
            LocalizedFormatters.date(newYear, locale: Locale(identifier: "en_US"), timeZone: utc),
            "Jan 1, 2000"
        )
        XCTAssertEqual(
            LocalizedFormatters.date(newYear, locale: Locale(identifier: "pt_BR"), timeZone: utc),
            "1 de jan. de 2000"
        )
        XCTAssertEqual(
            LocalizedFormatters.date(
                newYear, locale: Locale(identifier: "en_US"),
                timeZone: TimeZone(identifier: "Pacific/Auckland")!),
            "Jan 1, 2000",
            "midnight UTC is already the first in Auckland, not the previous day"
        )
    }

    func testAppLanguageMapsToTheExpectedInterfaceLocale() {
        XCTAssertEqual(
            AppLanguage.system.interfaceLocale.identifier,
            Locale.autoupdatingCurrent.identifier
        )
        XCTAssertEqual(AppLanguage.english.interfaceLocale.identifier, "en")
        XCTAssertEqual(AppLanguage.portugueseBrazil.interfaceLocale.identifier, "pt-BR")
    }
}
