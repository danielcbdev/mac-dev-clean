import Domain
import SwiftUI

/// Risk, shown as an icon, a word and a colour together.
///
/// Never colour alone: that would be unreadable for a large number of people
/// and invisible in a monochrome screenshot. The word is always present.
///
/// Nothing is ever labelled "guaranteed safe". The lowest level says "Low
/// risk", because there is no such thing as a guarantee here.
///
/// Pill shape and tokens per the redesign spec: 22pt tall, 6pt corner
/// radius, background tinted to match the foreground token.
struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Label(Self.title(risk), systemImage: Self.symbol(risk))
            .labelStyle(.titleAndIcon)
            .appFont(Typography.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Self.foreground(risk))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Self.background(risk), in: .rect(cornerRadius: Layout.badgeRadius))
            .accessibilityLabel(Self.title(risk))
    }

    static func title(_ risk: RiskLevel, locale: Locale = .current) -> String {
        switch risk {
        case .low: return LocalizedFormatters.text("Low risk", locale: locale)
        case .medium: return LocalizedFormatters.text("Medium risk", locale: locale)
        case .high: return LocalizedFormatters.text("High risk", locale: locale)
        }
    }

    static func symbol(_ risk: RiskLevel) -> String {
        switch risk {
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.circle"
        }
    }

    static func foreground(_ risk: RiskLevel) -> Color {
        switch risk {
        case .low: return Theme.success
        case .medium: return Theme.warning
        case .high: return Theme.danger
        }
    }

    static func background(_ risk: RiskLevel) -> Color {
        switch risk {
        case .low: return Theme.successBackground
        case .medium: return Theme.warningBackground
        case .high: return Theme.dangerBackground
        }
    }
}
