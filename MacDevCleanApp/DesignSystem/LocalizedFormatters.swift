import Domain
import Foundation

/// Formatting that remains truthful when a value is unavailable and honours
/// the locale selected for the interface.
enum LocalizedFormatters {
    static func bytes(_ bytes: UInt64?, locale: Locale) -> String {
        guard let bytes else {
            return localized("Unavailable", locale: locale)
        }
        return bytes.formatted(.byteCount(style: .file).locale(locale))
    }

    /// What assistive technology hears. "Unavailable" is enough beside a
    /// visible row label; read aloud on its own it says nothing about what is
    /// unavailable, so an unmeasured size announces itself in full.
    static func accessibleBytes(_ bytes: UInt64?, locale: Locale) -> String {
        guard bytes != nil else {
            return localized("Size could not be measured", locale: locale)
        }
        return self.bytes(bytes, locale: locale)
    }

    /// The time zone is a parameter because a date rendered in the host's zone
    /// is not reproducible: the same instant is a different day either side of
    /// midnight, which would make a test pass or fail depending on where it
    /// runs.
    static func date(
        _ date: Date, locale: Locale, timeZone: TimeZone = .current
    ) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, timeZone: timeZone)
                .year()
                .month(.abbreviated)
                .day()
        )
    }

    /// Resolves a catalog key that carries a count.
    ///
    /// The count goes through the catalog's plural variations rather than being
    /// pasted into a sentence, which is what keeps "1 categoria" and "8
    /// categorias" both grammatical. Xcode's inline `inflect: true` annotation
    /// is deliberately not used: it is an authoring convenience that resolves
    /// for only a few languages, and when it does not resolve it reaches the
    /// screen intact.
    static func count(_ key: String, _ value: Int, locale: Locale) -> String {
        String(format: localized(key, locale: locale), locale: locale, value)
    }

    /// Resolves a plain catalog key in the interface locale.
    ///
    /// `String(localized:)` consults the process's preferred localization, not
    /// the locale the interface is showing, so a string built that way ignores
    /// the in-app language setting. Everything the user reads goes through
    /// here instead.
    static func text(_ key: String, locale: Locale) -> String {
        localized(key, locale: locale)
    }

    /// Resolves a catalog key and substitutes already-formatted strings.
    ///
    /// The arguments are whole, translated fragments and the key owns the word
    /// order, so a translation can reorder them. Nothing is concatenated.
    static func text(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        String(format: localized(key, locale: locale), locale: locale, arguments: arguments)
    }

    static func localized(_ key: String, locale: Locale) -> String {
        let identifiers = [
            locale.identifier.replacingOccurrences(of: "_", with: "-"),
            locale.language.languageCode?.identifier,
        ].compactMap { $0 }

        for identifier in identifiers {
            if let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
                let bundle = Bundle(path: path)
            {
                return bundle.localizedString(forKey: key, value: key, table: nil)
            }
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}

extension AppLanguage {
    var interfaceLocale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .portugueseBrazil: Locale(identifier: "pt-BR")
        }
    }
}
