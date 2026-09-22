# Redesign Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared design-token layer (colors, typography, spacing/radius, risk badge, button styles) that every redesigned screen (Overview, Caches, History, Settings) will build on, matching the approved Claude Design spec exactly.

**Architecture:** Pure additions/edits inside `MacDevCleanApp/DesignSystem/`. No new package, no new target, no change to `Domain`/`CleanupRules`/`Scanning`/`Cleanup` — this is presentation-only. Colors are expressed as dynamic `NSColor`-backed `Color` values that resolve automatically under `.aqua`/`.darkAqua`, matching the spec's paired light/dark hex per token. Typography and metrics are plain structs/constants so they stay unit-testable without a UI-testing framework (this codebase has none).

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSColor`, `NSAppearance`), XCTest.

**Spec:** [docs/references/redesign/design-tokens.md](../../references/redesign/design-tokens.md) (distilled token table) and [docs/references/redesign/MacDevClean Redesign.dc.html](../../references/redesign/MacDevClean%20Redesign.dc.html) (full spec, screens `1a`–`1m`). Both were downloaded from the approved Claude Design project on 2026-09-22.

## Global Constraints

- Swift 6, macOS 14 minimum deployment.
- Native SwiftUI/AppKit only — no third-party dependency added for this work.
- Every color token must resolve correctly under both `.aqua` and `.darkAqua` (see spec table) — verified by tests that force each `NSAppearance`, not by eyeballing.
- Where the spec has no dark value for something (the disabled-button text color), the approximation and its reasoning must be a comment in the code, not a silently invented hex.
- Branch: work happens directly on `feature/new-design` (the current branch) — the owner explicitly authorized reusing it rather than cutting a new `feat/*` branch for this plan.
- Commits: small, Conventional Commits, one per task.
- Test target module name is `MacDevClean` (`@testable import MacDevClean`), matching existing tests in `MacDevCleanApp/MacDevCleanAppTests/`.

---

## Task 1: Dynamic hex-based colors

**Files:**
- Create: `MacDevCleanApp/DesignSystem/ColorSupport.swift`
- Test: `MacDevCleanApp/MacDevCleanAppTests/ColorSupportTests.swift`

**Interfaces:**
- Produces: `NSColor.init(hex: UInt32, alpha: CGFloat = 1)`, `Color.init(light: NSColor, dark: NSColor)`, `Color.init(lightHex: UInt32, darkHex: UInt32, alpha: CGFloat = 1)` — every later task builds colors with these.

- [ ] **Step 1: Write the failing test**

```swift
// MacDevCleanApp/MacDevCleanAppTests/ColorSupportTests.swift
import AppKit
import SwiftUI
import XCTest

@testable import MacDevClean

final class ColorSupportTests: XCTestCase {
    func testHexInitializerMatchesComponents() {
        let color = NSColor(hex: 0x1565E0)
        XCTAssertEqual(color.redComponent, CGFloat(0x15) / 255, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, CGFloat(0x65) / 255, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, CGFloat(0xE0) / 255, accuracy: 0.001)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001)
    }

    func testDynamicColorResolvesLightAndDarkSeparately() {
        let color = Color(lightHex: 0xFFFFFF, darkHex: 0x1C1C1E)

        let light = Self.resolve(color, appearance: .aqua)
        XCTAssertEqual(light.redComponent, 1, accuracy: 0.01)

        let dark = Self.resolve(color, appearance: .darkAqua)
        XCTAssertEqual(dark.redComponent, CGFloat(0x1C) / 255, accuracy: 0.01)
    }

    /// Shared by every color test in this target: forces a specific
    /// `NSAppearance` while resolving a dynamic `Color` down to concrete
    /// RGBA, the way AppKit resolves it when actually drawing.
    static func resolve(_ color: Color, appearance name: NSAppearance.Name) -> NSColor {
        let appearance = NSAppearance(named: name)!
        var resolved = NSColor.clear
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        }
        return resolved
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/ColorSupportTests 2>&1 | tail -40`
Expected: FAIL to build — `NSColor(hex:)`, `Color(light:dark:)` and `Color(lightHex:darkHex:)` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// MacDevCleanApp/DesignSystem/ColorSupport.swift
import AppKit
import SwiftUI

extension NSColor {
    /// A solid color from a `0xRRGGBB` value, as the design spec writes its
    /// tokens.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }
}

extension Color {
    /// A color that resolves differently under `.aqua` and `.darkAqua` — the
    /// way the design spec pairs a light and a dark value for every token.
    init(light: NSColor, dark: NSColor) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
    }

    /// Convenience for the common case: both sides are solid hex colors.
    init(lightHex: UInt32, darkHex: UInt32, alpha: CGFloat = 1) {
        self.init(
            light: NSColor(hex: lightHex, alpha: alpha),
            dark: NSColor(hex: darkHex, alpha: alpha))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/ColorSupportTests 2>&1 | tail -40`
Expected: PASS, 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add MacDevCleanApp/DesignSystem/ColorSupport.swift MacDevCleanApp/MacDevCleanAppTests/ColorSupportTests.swift
git commit -m "feat(design-system): add dynamic hex color helpers for the redesign"
```

---

## Task 2: Theme color tokens

**Files:**
- Create: `MacDevCleanApp/DesignSystem/Theme.swift`
- Test: `MacDevCleanApp/MacDevCleanAppTests/ThemeColorTests.swift`

**Interfaces:**
- Consumes: `Color.init(lightHex:darkHex:alpha:)`, `Color.init(light:dark:)` (Task 1); `ColorSupportTests.resolve(_:appearance:)` (Task 1, reused for resolution in this and later tasks).
- Produces: `Theme.background`, `.sidebarBackground`, `.cardBackground`, `.cardBorder`, `.separator`, `.textPrimary`, `.textSecondary`, `.textTertiary`, `.textDisabled`, `.accentFill`, `.accentOn`, `.accentText`, `.accentSoft`, `.success`, `.successBackground`, `.warning`, `.warningBackground`, `.danger`, `.dangerBackground`, `.control`, `.controlBorder`, `.controlSecondary`, `.neutral` — all `Color`, consumed by Tasks 5 and 6 and every later screen plan.

- [ ] **Step 1: Write the failing test**

```swift
// MacDevCleanApp/MacDevCleanAppTests/ThemeColorTests.swift
import AppKit
import SwiftUI
import XCTest

@testable import MacDevClean

final class ThemeColorTests: XCTestCase {
    private struct Token {
        let name: String
        let color: Color
        let light: UInt32
        let dark: UInt32
    }

    private static let tokens: [Token] = [
        Token(name: "background", color: Theme.background, light: 0xFFFFFF, dark: 0x1C1C1E),
        Token(name: "sidebarBackground", color: Theme.sidebarBackground, light: 0xEDEDF0, dark: 0x252528),
        Token(name: "cardBackground", color: Theme.cardBackground, light: 0xF7F7F9, dark: 0x232326),
        Token(name: "separator", color: Theme.separator, light: 0xE3E3E7, dark: 0x3A3A3E),
        Token(name: "textPrimary", color: Theme.textPrimary, light: 0x1D1D1F, dark: 0xF2F2F5),
        Token(name: "textSecondary", color: Theme.textSecondary, light: 0x5F5F66, dark: 0xA6A6AC),
        Token(name: "textTertiary", color: Theme.textTertiary, light: 0x76767C, dark: 0x98989E),
        Token(name: "accentFill", color: Theme.accentFill, light: 0x1565E0, dark: 0x3D8CF5),
        Token(name: "accentOn", color: Theme.accentOn, light: 0xFFFFFF, dark: 0x08182C),
        Token(name: "accentText", color: Theme.accentText, light: 0x0F5FD6, dark: 0x7DB8FF),
        Token(name: "accentSoft", color: Theme.accentSoft, light: 0xE8F0FE, dark: 0x16263D),
        Token(name: "success", color: Theme.success, light: 0x16733A, dark: 0x5BD08A),
        Token(name: "successBackground", color: Theme.successBackground, light: 0xE4F3E9, dark: 0x123324),
        Token(name: "warning", color: Theme.warning, light: 0x8A5300, dark: 0xF2B04A),
        Token(name: "warningBackground", color: Theme.warningBackground, light: 0xFBEFDC, dark: 0x3A2A10),
        Token(name: "danger", color: Theme.danger, light: 0xB02419, dark: 0xFF7B6E),
        Token(name: "dangerBackground", color: Theme.dangerBackground, light: 0xFBE9E7, dark: 0x3B1C18),
        Token(name: "control", color: Theme.control, light: 0xFFFFFF, dark: 0x3A3A3E),
        Token(name: "controlSecondary", color: Theme.controlSecondary, light: 0xF2F2F4, dark: 0x2E2E32),
        Token(name: "neutral", color: Theme.neutral, light: 0xEFEFF2, dark: 0x303034),
    ]

    func testEveryTokenMatchesTheSpecHexInBothAppearances() {
        for token in Self.tokens {
            assertHex(token.color, hex: token.light, appearance: .aqua, name: "\(token.name) light")
            assertHex(token.color, hex: token.dark, appearance: .darkAqua, name: "\(token.name) dark")
        }
    }

    func testCardBorderIsBlackNinePercentOnLightAndWhiteTwelvePercentOnDark() {
        let light = ColorSupportTests.resolve(Theme.cardBorder, appearance: .aqua)
        XCTAssertEqual(light.redComponent, 0, accuracy: 0.01)
        XCTAssertEqual(light.alphaComponent, 0.09, accuracy: 0.005)

        let dark = ColorSupportTests.resolve(Theme.cardBorder, appearance: .darkAqua)
        XCTAssertEqual(dark.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(dark.alphaComponent, 0.12, accuracy: 0.005)
    }

    func testControlBorderIsBlackFourteenPercentOnLightAndWhiteSixteenPercentOnDark() {
        let light = ColorSupportTests.resolve(Theme.controlBorder, appearance: .aqua)
        XCTAssertEqual(light.alphaComponent, 0.14, accuracy: 0.005)

        let dark = ColorSupportTests.resolve(Theme.controlBorder, appearance: .darkAqua)
        XCTAssertEqual(dark.alphaComponent, 0.16, accuracy: 0.005)
    }

    func testTextDisabledIsDocumentedAsAnApproximationNotASpecValue() {
        // The spec never shows a disabled control on a live screen, and its
        // one demo swatch gives no dark value. This just locks the chosen
        // approximation so nobody swaps it silently.
        let light = ColorSupportTests.resolve(Theme.textDisabled, appearance: .aqua)
        assertComponents(light, hex: 0xA0A0A6, name: "textDisabled light")
        let dark = ColorSupportTests.resolve(Theme.textDisabled, appearance: .darkAqua)
        assertComponents(dark, hex: 0x98989E, name: "textDisabled dark")
    }

    // MARK: - Helpers

    private func assertHex(
        _ color: Color, hex: UInt32, appearance: NSAppearance.Name, name: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let resolved = ColorSupportTests.resolve(color, appearance: appearance)
        assertComponents(resolved, hex: hex, name: name, file: file, line: line)
    }

    private func assertComponents(
        _ resolved: NSColor, hex: UInt32, name: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            resolved.redComponent, CGFloat((hex >> 16) & 0xFF) / 255, accuracy: 0.01,
            "\(name) red", file: file, line: line)
        XCTAssertEqual(
            resolved.greenComponent, CGFloat((hex >> 8) & 0xFF) / 255, accuracy: 0.01,
            "\(name) green", file: file, line: line)
        XCTAssertEqual(
            resolved.blueComponent, CGFloat(hex & 0xFF) / 255, accuracy: 0.01,
            "\(name) blue", file: file, line: line)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/ThemeColorTests 2>&1 | tail -40`
Expected: FAIL to build — `Theme` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// MacDevCleanApp/DesignSystem/Theme.swift
import SwiftUI

/// Color tokens from the approved redesign spec — see
/// `docs/references/redesign/design-tokens.md`. Every token is defined for
/// both `.aqua` and `.darkAqua`; SwiftUI resolves the right one when drawing.
enum Theme {
    static let background = Color(lightHex: 0xFFFFFF, darkHex: 0x1C1C1E)
    static let sidebarBackground = Color(lightHex: 0xEDEDF0, darkHex: 0x252528)
    static let cardBackground = Color(lightHex: 0xF7F7F9, darkHex: 0x232326)
    static let cardBorder = Color(
        light: NSColor.black.withAlphaComponent(0.09),
        dark: NSColor.white.withAlphaComponent(0.12))
    static let separator = Color(lightHex: 0xE3E3E7, darkHex: 0x3A3A3E)

    static let textPrimary = Color(lightHex: 0x1D1D1F, darkHex: 0xF2F2F5)
    static let textSecondary = Color(lightHex: 0x5F5F66, darkHex: 0xA6A6AC)
    static let textTertiary = Color(lightHex: 0x76767C, darkHex: 0x98989E)

    static let accentFill = Color(lightHex: 0x1565E0, darkHex: 0x3D8CF5)
    static let accentOn = Color(lightHex: 0xFFFFFF, darkHex: 0x08182C)
    static let accentText = Color(lightHex: 0x0F5FD6, darkHex: 0x7DB8FF)
    static let accentSoft = Color(lightHex: 0xE8F0FE, darkHex: 0x16263D)

    static let success = Color(lightHex: 0x16733A, darkHex: 0x5BD08A)
    static let successBackground = Color(lightHex: 0xE4F3E9, darkHex: 0x123324)
    static let warning = Color(lightHex: 0x8A5300, darkHex: 0xF2B04A)
    static let warningBackground = Color(lightHex: 0xFBEFDC, darkHex: 0x3A2A10)
    static let danger = Color(lightHex: 0xB02419, darkHex: 0xFF7B6E)
    static let dangerBackground = Color(lightHex: 0xFBE9E7, darkHex: 0x3B1C18)

    static let control = Color(lightHex: 0xFFFFFF, darkHex: 0x3A3A3E)
    static let controlBorder = Color(
        light: NSColor.black.withAlphaComponent(0.14),
        dark: NSColor.white.withAlphaComponent(0.16))
    static let controlSecondary = Color(lightHex: 0xF2F2F4, darkHex: 0x2E2E32)
    static let neutral = Color(lightHex: 0xEFEFF2, darkHex: 0x303034)

    /// Not present on any of the spec's 13 screen frames — the spec's only
    /// disabled control is in the light-mode "system swatch" demo block, and
    /// that block gives no dark hex. Approximated as `textTertiary`'s dark
    /// value so a disabled control still reads as muted, rather than
    /// inventing an unconfirmed hex. Revisit if a later screen shows a
    /// disabled control explicitly.
    static let textDisabled = Color(lightHex: 0xA0A0A6, darkHex: 0x98989E)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/ThemeColorTests 2>&1 | tail -40`
Expected: PASS, 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add MacDevCleanApp/DesignSystem/Theme.swift MacDevCleanApp/MacDevCleanAppTests/ThemeColorTests.swift
git commit -m "feat(design-system): add Theme color tokens from the redesign spec"
```

---

## Task 3: Typography tokens

**Files:**
- Create: `MacDevCleanApp/DesignSystem/Typography.swift`
- Test: `MacDevCleanApp/MacDevCleanAppTests/TypographyTests.swift`

**Interfaces:**
- Produces: `struct AppFont { let size: CGFloat; let weight: Font.Weight; let tabularNumbers: Bool; var font: Font }`; `Typography.hero`, `.metric`, `.title`, `.body`, `.caption` (all `AppFont`); `View.appFont(_ token: AppFont) -> some View`. Consumed by Tasks 5 and 6 and every later screen plan.

- [ ] **Step 1: Write the failing test**

```swift
// MacDevCleanApp/MacDevCleanAppTests/TypographyTests.swift
import SwiftUI
import XCTest

@testable import MacDevClean

final class TypographyTests: XCTestCase {
    func testHeroIsThirtyFourBold() {
        XCTAssertEqual(Typography.hero.size, 34)
        XCTAssertEqual(Typography.hero.weight, .bold)
        XCTAssertFalse(Typography.hero.tabularNumbers)
    }

    func testMetricIsFortyTwoBoldWithTabularDigits() {
        XCTAssertEqual(Typography.metric.size, 42)
        XCTAssertEqual(Typography.metric.weight, .bold)
        XCTAssertTrue(Typography.metric.tabularNumbers)
    }

    func testTitleIsSeventeenSemibold() {
        XCTAssertEqual(Typography.title.size, 17)
        XCTAssertEqual(Typography.title.weight, .semibold)
        XCTAssertFalse(Typography.title.tabularNumbers)
    }

    func testBodyIsThirteenRegular() {
        XCTAssertEqual(Typography.body.size, 13)
        XCTAssertEqual(Typography.body.weight, .regular)
    }

    func testCaptionIsElevenMedium() {
        XCTAssertEqual(Typography.caption.size, 11)
        XCTAssertEqual(Typography.caption.weight, .medium)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/TypographyTests 2>&1 | tail -40`
Expected: FAIL to build — `Typography` and `AppFont` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// MacDevCleanApp/DesignSystem/Typography.swift
import SwiftUI

/// One typographic style: a size and weight from the spec's scale, plus
/// whether it always carries tabular (monospaced) digits.
struct AppFont {
    let size: CGFloat
    let weight: Font.Weight
    let tabularNumbers: Bool

    init(size: CGFloat, weight: Font.Weight, tabularNumbers: Bool = false) {
        self.size = size
        self.weight = weight
        self.tabularNumbers = tabularNumbers
    }

    var font: Font { .system(size: size, weight: weight) }
}

/// The spec's type scale — see `docs/references/redesign/design-tokens.md`.
/// SwiftUI's `Font.Weight` only exposes stops at 400/500/600/700 near this
/// range, so the spec's "650" titles render at `.semibold` (600), the
/// nearest stop below 700.
enum Typography {
    static let hero = AppFont(size: 34, weight: .bold)
    static let metric = AppFont(size: 42, weight: .bold, tabularNumbers: true)
    static let title = AppFont(size: 17, weight: .semibold)
    static let body = AppFont(size: 13, weight: .regular)
    static let caption = AppFont(size: 11, weight: .medium)
}

extension View {
    /// Applies an `AppFont`, including tabular digits when the token calls
    /// for them — the spec asks for this on every number so totals don't
    /// visually jitter as they update.
    @ViewBuilder
    func appFont(_ token: AppFont) -> some View {
        if token.tabularNumbers {
            self.font(token.font).monospacedDigit()
        } else {
            self.font(token.font)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/TypographyTests 2>&1 | tail -40`
Expected: PASS, 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add MacDevCleanApp/DesignSystem/Typography.swift MacDevCleanApp/MacDevCleanAppTests/TypographyTests.swift
git commit -m "feat(design-system): add Typography tokens from the redesign spec"
```

---

## Task 4: Spacing and radius scale

**Files:**
- Modify: `MacDevCleanApp/DesignSystem/Spacing.swift`
- Test: `MacDevCleanApp/MacDevCleanAppTests/LayoutScaleTests.swift`

**Interfaces:**
- Produces: `Layout.space4/8/12/16/20/24/32`, `Layout.controlRadius`, `Layout.badgeRadius` (all `CGFloat`, added to the existing `Layout` enum whose `cardRadius` already equals the spec's 12). Consumed by Tasks 5 and 6 and every later screen plan.

- [ ] **Step 1: Write the failing test**

```swift
// MacDevCleanApp/MacDevCleanAppTests/LayoutScaleTests.swift
import XCTest

@testable import MacDevClean

final class LayoutScaleTests: XCTestCase {
    func testSpacingScaleMatchesSpec() {
        XCTAssertEqual(Layout.space4, 4)
        XCTAssertEqual(Layout.space8, 8)
        XCTAssertEqual(Layout.space12, 12)
        XCTAssertEqual(Layout.space16, 16)
        XCTAssertEqual(Layout.space20, 20)
        XCTAssertEqual(Layout.space24, 24)
        XCTAssertEqual(Layout.space32, 32)
    }

    func testRadiusScaleMatchesSpec() {
        XCTAssertEqual(Layout.cardRadius, 12)
        XCTAssertEqual(Layout.controlRadius, 8)
        XCTAssertEqual(Layout.badgeRadius, 6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/LayoutScaleTests 2>&1 | tail -40`
Expected: FAIL to build — `Layout.space4` etc. and `Layout.controlRadius`/`.badgeRadius` don't exist yet (`Layout.cardRadius` already does and already equals 12).

- [ ] **Step 3: Write minimal implementation**

Append to the existing `Layout` enum in `MacDevCleanApp/DesignSystem/Spacing.swift` (do not touch the existing members):

```swift
extension Layout {
    /// The redesign spec's spacing scale, in ascending order.
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32

    /// `cardRadius` above already equals the spec's card radius (12).
    static let controlRadius: CGFloat = 8
    static let badgeRadius: CGFloat = 6
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/LayoutScaleTests 2>&1 | tail -40`
Expected: PASS, 2 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add MacDevCleanApp/DesignSystem/Spacing.swift MacDevCleanApp/MacDevCleanAppTests/LayoutScaleTests.swift
git commit -m "feat(design-system): add spacing and radius scale from the redesign spec"
```

---

## Task 5: Redesign RiskBadge as a tinted pill

**Files:**
- Modify: `MacDevCleanApp/DesignSystem/RiskBadge.swift`
- Test: `MacDevCleanApp/MacDevCleanAppTests/RiskBadgeTests.swift`

**Interfaces:**
- Consumes: `Theme.success/.successBackground/.warning/.warningBackground/.danger/.dangerBackground` (Task 2), `Typography.caption` + `View.appFont` (Task 3), `Layout.badgeRadius` (Task 4), `ColorSupportTests.resolve` (Task 1).
- Produces: `RiskBadge` keeps its existing public API (`RiskBadge(risk: RiskLevel)`, used unchanged at its 6 existing call sites) plus newly-public static helpers `RiskBadge.foreground(_:)` and `RiskBadge.background(_:)` (both `(RiskLevel) -> Color`) for later screens/tests to reuse.

- [ ] **Step 1: Write the failing test**

```swift
// MacDevCleanApp/MacDevCleanAppTests/RiskBadgeTests.swift
import AppKit
import Domain
import SwiftUI
import XCTest

@testable import MacDevClean

final class RiskBadgeTests: XCTestCase {
    func testTitlesAreUnchanged() {
        XCTAssertEqual(RiskBadge.title(.low), "Low risk")
        XCTAssertEqual(RiskBadge.title(.medium), "Medium risk")
        XCTAssertEqual(RiskBadge.title(.high), "High risk")
    }

    func testSymbolsMatchTheSpecShapes() {
        XCTAssertEqual(RiskBadge.symbol(.low), "checkmark.shield")
        XCTAssertEqual(RiskBadge.symbol(.medium), "exclamationmark.triangle")
        // The spec's high-risk icon is a circle with an exclamation mark, not
        // an octagon — deliberately changed from the prior implementation to
        // match it exactly.
        XCTAssertEqual(RiskBadge.symbol(.high), "exclamationmark.circle")
    }

    func testEachRiskLevelUsesItsOwnTokenPairNotAnother() {
        let pairs: [(RiskLevel, Color, Color)] = [
            (.low, Theme.success, Theme.successBackground),
            (.medium, Theme.warning, Theme.warningBackground),
            (.high, Theme.danger, Theme.dangerBackground),
        ]
        for (risk, expectedForeground, expectedBackground) in pairs {
            let foreground = ColorSupportTests.resolve(RiskBadge.foreground(risk), appearance: .aqua)
            let expectedFg = ColorSupportTests.resolve(expectedForeground, appearance: .aqua)
            XCTAssertEqual(foreground, expectedFg, "\(risk) foreground")

            let background = ColorSupportTests.resolve(RiskBadge.background(risk), appearance: .aqua)
            let expectedBg = ColorSupportTests.resolve(expectedBackground, appearance: .aqua)
            XCTAssertEqual(background, expectedBg, "\(risk) background")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/RiskBadgeTests 2>&1 | tail -40`
Expected: FAIL — `RiskBadge.foreground`/`.background` don't exist yet, and `RiskBadge.symbol(.high)` currently returns `"exclamationmark.octagon"`, not `"exclamationmark.circle"`.

- [ ] **Step 3: Write minimal implementation**

Replace the full contents of `MacDevCleanApp/DesignSystem/RiskBadge.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/RiskBadgeTests 2>&1 | tail -40`
Expected: PASS, 3 tests, 0 failures.

Then run the full suite once to confirm the six existing `RiskBadge` call sites still compile:

Run: `bash scripts/verify.sh`
Expected: exit 0, all existing tests still pass (no call site references `RiskBadge.symbol`/`.foreground`/`.background` today, so this is additive).

- [ ] **Step 5: Commit**

```bash
git add MacDevCleanApp/DesignSystem/RiskBadge.swift MacDevCleanApp/MacDevCleanAppTests/RiskBadgeTests.swift
git commit -m "feat(design-system): restyle RiskBadge as a tinted pill per the redesign spec"
```

---

## Task 6: Primary / Secondary / Destructive button styles

**Files:**
- Create: `MacDevCleanApp/DesignSystem/ButtonStyles.swift`
- Test: `MacDevCleanApp/MacDevCleanAppTests/ButtonStyleTests.swift`

**Interfaces:**
- Consumes: `Theme.accentFill/.accentOn/.textPrimary/.control/.controlBorder/.danger` (Task 2), `Typography.body` + `View.appFont` (Task 3), `Layout.controlRadius` (Task 4).
- Produces: `PrimaryButtonStyle`, `SecondaryButtonStyle`, `DestructiveButtonStyle` (all `ButtonStyle`), each with public `static let height: CGFloat` and `static let horizontalPadding: CGFloat`; static `ButtonStyle` accessors `.macDevPrimary`, `.macDevSecondary`, `.macDevDestructive`. Later screen plans apply these via `.buttonStyle(.macDevPrimary)` etc., replacing the current `.buttonStyle(.borderedProminent)` / default-bordered usages — that rewiring is out of scope for this task; this task only builds the styles.

- [ ] **Step 1: Write the failing test**

```swift
// MacDevCleanApp/MacDevCleanAppTests/ButtonStyleTests.swift
import XCTest

@testable import MacDevClean

final class ButtonStyleTests: XCTestCase {
    func testPrimaryMetricsMatchSpec() {
        XCTAssertEqual(PrimaryButtonStyle.height, 32)
        // The spec pads primary buttons 18pt horizontally — a one-off, not
        // on the 4/8/12/16/20/24/32 spacing scale.
        XCTAssertEqual(PrimaryButtonStyle.horizontalPadding, 18)
    }

    func testSecondaryMetricsMatchSpec() {
        XCTAssertEqual(SecondaryButtonStyle.height, 32)
        XCTAssertEqual(SecondaryButtonStyle.horizontalPadding, 16)
    }

    func testDestructiveMetricsMatchSpec() {
        XCTAssertEqual(DestructiveButtonStyle.height, 32)
        XCTAssertEqual(DestructiveButtonStyle.horizontalPadding, 16)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/ButtonStyleTests 2>&1 | tail -40`
Expected: FAIL to build — `PrimaryButtonStyle`/`SecondaryButtonStyle`/`DestructiveButtonStyle` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// MacDevCleanApp/DesignSystem/ButtonStyles.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd MacDevCleanApp && xcodebuild test -scheme MacDevClean -destination 'platform=macOS' -only-testing:MacDevCleanAppTests/ButtonStyleTests 2>&1 | tail -40`
Expected: PASS, 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add MacDevCleanApp/DesignSystem/ButtonStyles.swift MacDevCleanApp/MacDevCleanAppTests/ButtonStyleTests.swift
git commit -m "feat(design-system): add primary, secondary and destructive button styles"
```

---

## Task 7: Full verification and progress record

**Files:**
- Modify: `docs/progress.md`

**Interfaces:**
- Consumes: nothing new — this task only runs the full gate and records the result.

- [ ] **Step 1: Run the full verification gate**

Run: `MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh`
Expected: exit 0. Record the actual test count and any deviation — do not copy a number from a previous milestone.

- [ ] **Step 2: Update `docs/progress.md`**

Add a row to the "Plan status" table:

```markdown
| redesign foundation | feature/new-design | in progress — design tokens landed, screens not yet redesigned |
```

Update "Current state" to point at this plan and note the real `scripts/verify.sh` exit status, date and test count observed in Step 1 — following the file's existing format exactly (see the entries for plan 10).

- [ ] **Step 3: Commit**

```bash
git add docs/progress.md
git commit -m "docs: record redesign-foundation verification evidence"
```

---

## Self-Review

**Spec coverage:** every token in `docs/references/redesign/design-tokens.md` — 22 colors (Task 2), 1 approximated disabled-text color (Task 2), 5 typography styles (Task 3), 7 spacing steps + 2 radii (Task 4) — has a task. The risk-badge pill shape (Task 5) and the three button variants (Task 6) are the only *components* the spec's system block shows outside a screen frame; per-screen layout (sidebar, cards, rings, tables) is explicitly out of scope for this plan and belongs to the per-screen plans that follow it.

**Placeholder scan:** no `TBD`/`TODO`/"handle appropriately" language; every step has real code or a real shell command.

**Type consistency:** `Color`/`AppFont`/`CGFloat` types match across every task that consumes an earlier task's output (checked `Theme.*` against `Color`, `Typography.*` against `AppFont`, `Layout.*` against `CGFloat`, `RiskBadge.foreground/background` return `Color` as `Theme` does).
