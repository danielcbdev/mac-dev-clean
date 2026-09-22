import SwiftUI

/// Primary action: filled with the accent color. At most one per screen —
/// a screen with two "loudest" buttons has no loudest button.
struct PrimaryButtonStyle: ButtonStyle {
    static let height: CGFloat = 32
    static let horizontalPadding: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(Typography.body)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.accentOn)
            .padding(.horizontal, Self.horizontalPadding)
            .frame(height: Self.height)
            .background(
                Theme.accentFill.opacity(configuration.isPressed ? 0.85 : 1),
                in: .rect(cornerRadius: Layout.controlRadius))
    }
}

/// Secondary action: outlined, neutral fill.
struct SecondaryButtonStyle: ButtonStyle {
    static let height: CGFloat = 32
    static let horizontalPadding: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(Typography.body)
            .fontWeight(.medium)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Self.horizontalPadding)
            .frame(height: Self.height)
            .background(Theme.control, in: .rect(cornerRadius: Layout.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.controlRadius)
                    .strokeBorder(Theme.controlBorder, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Destructive action: outlined in the danger color, never filled — a
/// filled destructive button reads as the default choice, and removal is
/// never the default choice here.
struct DestructiveButtonStyle: ButtonStyle {
    static let height: CGFloat = 32
    static let horizontalPadding: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(Typography.body)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.danger)
            .padding(.horizontal, Self.horizontalPadding)
            .frame(height: Self.height)
            .background(Theme.control, in: .rect(cornerRadius: Layout.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.controlRadius)
                    .strokeBorder(Theme.danger.opacity(0.35), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var macDevPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var macDevSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    static var macDevDestructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}
