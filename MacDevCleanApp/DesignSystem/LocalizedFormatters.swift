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

    static func date(_ date: Date, locale: Locale) -> String {
        date.formatted(
            .dateTime
                .year()
                .month(.abbreviated)
                .day()
                .locale(locale)
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
