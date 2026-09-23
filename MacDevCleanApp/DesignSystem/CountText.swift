import SwiftUI

/// A count the user reads.
///
/// This type exists because of a defect, and its shape is the lesson. Counts
/// used to be written inline with Xcode's automatic grammar agreement markup —
/// the `inflect: true` annotation — directly inside a `Text`. That markup is an
/// authoring convenience: when the catalog resolves it, the user sees "2
/// items"; when it does not — which is every language the agreement does not
/// cover, and every entry stored as a flat value rather than as plural
/// variations — the annotation itself reaches the screen. It did.
///
/// Going through one type means a count has exactly one path to the screen, the
/// path is the one `CatalogRenderingTests` resolves, and it honours the locale
/// the interface is showing rather than the process's preferred language.
struct CountText: View {
    @Environment(\.locale) private var locale

    private let key: String
    private let value: Int

    /// - Parameters:
    ///   - key: a catalog key carrying `%lld` and declaring plural variations.
    ///   - value: the count to render.
    init(_ key: String, _ value: Int) {
        self.key = key
        self.value = value
    }

    var body: some View {
        Text(LocalizedFormatters.count(key, value, locale: locale))
    }
}
