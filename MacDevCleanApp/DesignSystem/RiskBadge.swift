import Domain
import SwiftUI

/// Risk, shown as an icon, a word and a colour together.
///
/// Never colour alone: that would be unreadable for a large number of people
/// and invisible in a monochrome screenshot. The word is always present.
///
/// Nothing is ever labelled "guaranteed safe". The lowest level says "Low
/// risk", because there is no such thing as a guarantee here.
struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Label(Self.title(risk), systemImage: Self.symbol(risk))
            .font(.caption)
            .foregroundStyle(Self.color(risk))
            .accessibilityLabel(Self.title(risk))
    }

    static func title(_ risk: RiskLevel) -> String {
        switch risk {
        case .low: return String(localized: "Low risk")
        case .medium: return String(localized: "Medium risk")
        case .high: return String(localized: "High risk")
        }
    }

    static func symbol(_ risk: RiskLevel) -> String {
        switch risk {
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.octagon"
        }
    }

    static func color(_ risk: RiskLevel) -> Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}
