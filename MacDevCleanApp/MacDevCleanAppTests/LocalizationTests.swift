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

    func testFormattersUseTheRequestedLocaleForBytesAndDates() {
        XCTAssertEqual(
            LocalizedFormatters.bytes(1_500_000, locale: Locale(identifier: "en_US")),
            "1.5 MB"
        )
        XCTAssertEqual(
            LocalizedFormatters.bytes(1_500_000, locale: Locale(identifier: "pt_BR")),
            "1,5 MB"
        )

        let middayUTC = Date(timeIntervalSince1970: 946_728_000)
        XCTAssertEqual(
            LocalizedFormatters.date(middayUTC, locale: Locale(identifier: "en_US")),
            "Jan 1, 2000"
        )
        XCTAssertEqual(
            LocalizedFormatters.date(middayUTC, locale: Locale(identifier: "pt_BR")),
            "1 de jan. de 2000"
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
