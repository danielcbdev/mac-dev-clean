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

    private static func localized(_ key: String, locale: Locale) -> String {
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
