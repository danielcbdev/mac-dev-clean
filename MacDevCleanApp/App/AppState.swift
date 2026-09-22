import Foundation
import SwiftUI

/// Where the application is in its one and only workflow.
///
/// Modelled as a single enumeration so invalid combinations cannot be written
/// down: the app is never "scanning" and "cleaning" at once, and revisiting a
/// screen cannot start a second scan because the state already says one is
/// running.
enum AppState: Equatable {
    /// No roots have been accepted yet. Nothing is scanned until they are.
    case onboarding
    case idle
    case scanning
    case results
    case reviewing
    case cleaning
    case completed

    var isBusy: Bool { self == .scanning || self == .cleaning }
}

/// The sidebar destinations, in order.
enum Destination: String, CaseIterable, Identifiable, Hashable {
    case overview, caches, largeFiles, history, exclusions, settings

    var id: String { rawValue }

    /// English text doubles as the String Catalog key, which is the catalog's
    /// own convention. Brazilian Portuguese is supplied against these keys.
    var title: LocalizedStringKey {
        switch self {
        case .overview: return "Overview"
        case .caches: return "Caches"
        case .largeFiles: return "Large Files"
        case .history: return "History"
        case .exclusions: return "Exclusions"
        case .settings: return "Settings"
        }
    }

    var plainTitle: String {
        switch self {
        case .overview: return String(localized: "Overview")
        case .caches: return String(localized: "Caches")
        case .largeFiles: return String(localized: "Large Files")
        case .history: return String(localized: "History")
        case .exclusions: return String(localized: "Exclusions")
        case .settings: return String(localized: "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "house"
        case .caches: return "cylinder.split.1x2"
        case .largeFiles: return "folder"
        case .history: return "clock"
        case .exclusions: return "hand.raised"
        case .settings: return "gearshape"
        }
    }

    /// Stable identifier for UI automation. Never a path.
    var accessibilityID: String { "sidebar.\(rawValue)" }

    /// What the detail area shows for this destination.
    ///
    /// The routing table is data rather than control flow on purpose. A
    /// `switch` buried in a view is what let a finished feature keep
    /// advertising itself as missing: plan 06 built Large Files — the screen,
    /// the model, the scanner and ten tests — and the one line in `ContentView`
    /// that returned a placeholder was never changed. Nothing failed, because
    /// nothing was watching. Now something is.
    enum ScreenKind: String, Equatable, CaseIterable {
        case overview, caches, largeFiles, history, exclusions, settings
        /// No screen exists yet. A destination in this state is never offered.
        case placeholder
    }

    var screenKind: ScreenKind {
        switch self {
        case .overview: return .overview
        case .caches: return .caches
        case .largeFiles: return .largeFiles
        case .history: return .history
        case .exclusions: return .exclusions
        case .settings: return .settings
        }
    }

    /// True when choosing this destination opens a screen.
    var isAvailable: Bool { screenKind != .placeholder }

    /// The destinations the sidebar offers, in order.
    ///
    /// A destination with no screen is not offered at all. An entry that leads
    /// to "this is not built yet" is worse than an absent entry: it spends the
    /// user's attention and gives nothing back.
    static var sidebarItems: [Destination] { allCases.filter(\.isAvailable) }
}
