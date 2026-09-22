import Foundation
import XCTest

@testable import MacDevClean

/// Proves that what the catalog holds is what a person can read.
///
/// The defect these tests exist for was not a missing translation: the string
/// was found and translated, and still reached the screen carrying
/// `^[...](inflect: true)`. A test that only checked "is there a pt-BR value"
/// would have passed throughout. So these resolve every key the way the
/// application resolves it, at several counts, in both languages, and look at
/// the result.
@MainActor
final class CatalogRenderingTests: XCTestCase {
    private static let languages = ["en", "pt-BR"]

    // MARK: - The regression gate

    func testNoResolvedStringLeaksInflectionMarkup() throws {
        let keys = try Self.catalogKeys()
        XCTAssertGreaterThan(keys.count, 200, "the catalog was not loaded")

        for key in keys {
            for count in [0, 1, 2] {
                for language in Self.languages {
                    let rendered = Self.render(key, count: count, language: language)
                    XCTAssertFalse(
                        rendered.contains("^["),
                        "\(language) \(key) at \(count) still shows markup: \(rendered)")
                    XCTAssertFalse(
                        rendered.contains("](inflect:"),
                        "\(language) \(key) at \(count) still shows markup: \(rendered)")
                }
            }
        }
    }

    /// A key that never resolves is as broken as one that resolves to markup:
    /// the user reads the English key. This catches a key deleted from the
    /// catalog while a call site still asks for it.
    func testEveryCatalogKeyResolvesInBothLanguages() throws {
        for key in try Self.catalogKeys() {
            for language in Self.languages {
                let format = LocalizedFormatters.localized(
                    key, locale: Locale(identifier: language))
                XCTAssertFalse(
                    format.isEmpty, "\(language) \(key) resolved to an empty string")
            }
        }
    }

    // MARK: - The two strings the owner reported

    func testTheCacheCategoriesHeaderCountsCategoriesAsWords() {
        XCTAssertEqual(Self.render("%lld category", count: 0, language: "en"), "0 categories")
        XCTAssertEqual(Self.render("%lld category", count: 1, language: "en"), "1 category")
        XCTAssertEqual(Self.render("%lld category", count: 8, language: "en"), "8 categories")

        XCTAssertEqual(Self.render("%lld category", count: 0, language: "pt-BR"), "0 categorias")
        XCTAssertEqual(Self.render("%lld category", count: 1, language: "pt-BR"), "1 categoria")
        XCTAssertEqual(Self.render("%lld category", count: 8, language: "pt-BR"), "8 categorias")
    }

    func testTheScanStatusLineReadsAsASentenceInBothLanguages() {
        XCTAssertEqual(
            Self.status(items: 193, categories: 8, language: "en"),
            "Found 193 items across 8 categories.")
        XCTAssertEqual(
            Self.status(items: 1, categories: 1, language: "en"),
            "Found 1 item across 1 category.")

        XCTAssertEqual(
            Self.status(items: 193, categories: 8, language: "pt-BR"),
            "O MacDevClean encontrou 193 itens em 8 categorias.")
        XCTAssertEqual(
            Self.status(items: 1, categories: 1, language: "pt-BR"),
            "O MacDevClean encontrou 1 item em 1 categoria.")
    }

    /// The count and the size in one line. This was
    /// `Text("^[...](inflect: true) · " + ByteLabel.format(...))`, which chose
    /// the verbatim `Text` overload and skipped localization entirely.
    func testACountAndASizeShareOneTranslatableKey() {
        let locale = Locale(identifier: "pt-BR")
        let rendered = LocalizedFormatters.text(
            "%1$@ · %2$@", locale: locale,
            LocalizedFormatters.count("%lld category", 8, locale: locale),
            "1,5 MB")

        XCTAssertEqual(rendered, "8 categorias · 1,5 MB")
    }

    /// The sentence that was always English, in both languages, because it was
    /// built with `+`.
    func testTheTrashDisclaimerIsTranslatedAndNeverClaimsSpaceIsFreed() {
        let english = LocalizedFormatters.text(
            "About %@ will move to the Trash. That frees space only when you empty it.",
            locale: Locale(identifier: "en"), "1.5 MB")
        let portuguese = LocalizedFormatters.text(
            "About %@ will move to the Trash. That frees space only when you empty it.",
            locale: Locale(identifier: "pt-BR"), "1,5 MB")

        XCTAssertEqual(
            english, "About 1.5 MB will move to the Trash. That frees space only when you empty it."
        )
        XCTAssertNotEqual(portuguese, english, "the sentence must not stay English in pt-BR")
        XCTAssertTrue(portuguese.contains("Lixeira"), portuguese)
        XCTAssertTrue(portuguese.contains("1,5 MB"), portuguese)
    }

    /// A key written across several source lines is the one most likely to
    /// drift from the catalog by a single space. When it does, the resolver
    /// returns the key, and the user reads `%lld`.
    func testTheMultiLineKeysTheViewsRequestExistInTheCatalog() throws {
        let catalog = try Self.catalog()
        let requested = [
            "%lld resource reported no size. MacDevClean does not mount volumes to work one out.",
            "%lld row shown for information only and cannot be selected.",
            "%lld item could not be measured and is not included in this total.",
            "About %@ will move to the Trash. That frees space only when you empty it.",
        ]

        for key in requested {
            XCTAssertNotNil(catalog[key], "the catalog has no key \(key)")
            XCTAssertFalse(
                Self.render(key, count: 2, language: "pt-BR").contains("%lld"),
                "\(key) resolved to itself, so the catalog does not hold it")
        }
    }

    // MARK: - Catalog shape

    /// Both languages must declare the same plural categories. A `one` that
    /// exists in English and not in Portuguese resolves to the key at count 1.
    func testEveryCountingKeyDeclaresMatchingPluralCategoriesInBothLanguages() throws {
        let catalog = try Self.catalog()
        var checked = 0

        for (key, entry) in catalog where key.contains("%lld") {
            guard let localizations = entry["localizations"] as? [String: Any] else {
                return XCTFail("\(key): no localizations")
            }
            let english = Self.pluralCategories(in: localizations["en"])
            let portuguese = Self.pluralCategories(in: localizations["pt-BR"])

            XCTAssertFalse(
                english.isEmpty,
                "\(key) counts something but declares no plural variations in en")
            XCTAssertEqual(
                english, portuguese,
                "\(key) declares different plural categories per language")
            checked += 1
        }

        XCTAssertGreaterThanOrEqual(checked, 13, "the counting keys were not found")
    }

    // MARK: - Helpers

    /// The application resolves counts through `LocalizedFormatters`, and so
    /// does this. A test with its own lookup would prove something the app
    /// never does.
    static func render(_ key: String, count: Int, language: String) -> String {
        let locale = Locale(identifier: language)
        guard key.contains("%lld") else {
            return LocalizedFormatters.localized(key, locale: locale)
        }
        return LocalizedFormatters.count(key, count, locale: locale)
    }

    private static func status(items: Int, categories: Int, language: String) -> String {
        let locale = Locale(identifier: language)
        return LocalizedFormatters.text(
            "Found %1$@ across %2$@.", locale: locale,
            LocalizedFormatters.count("%lld item", items, locale: locale),
            LocalizedFormatters.count("%lld category", categories, locale: locale))
    }

    private static func pluralCategories(in localization: Any?) -> Set<String> {
        guard let dictionary = localization as? [String: Any],
            let variations = dictionary["variations"] as? [String: Any],
            let plural = variations["plural"] as? [String: Any]
        else { return [] }
        return Set(plural.keys)
    }

    static func catalogKeys() throws -> [String] {
        try catalog().keys.sorted()
    }

    /// Read from the source catalog rather than the compiled bundle: the point
    /// is to check every key the project declares, including one no call site
    /// uses yet.
    static func catalog() throws -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        guard let root = object as? [String: Any],
            let strings = root["strings"] as? [String: [String: Any]]
        else {
            throw NSError(
                domain: "CatalogRenderingTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Localizable.xcstrings is not a catalog"])
        }
        return strings
    }
}
