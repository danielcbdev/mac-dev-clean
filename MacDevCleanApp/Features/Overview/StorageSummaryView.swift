import Domain
import SwiftUI

/// The ring from the approved reference, with the wording corrected.
///
/// Two things the mockup got wrong and this does not:
///
/// - It says **"Potential cleanup"**, not "reclaimable". Moving items to the
///   Trash frees nothing until the Trash is emptied, so promising reclaimed
///   space here would be false.
/// - Its denominator is the **sum of known filesystem candidate sizes**, not
///   the size of the disk. A ring measured against the whole disk would imply a
///   proportion nobody computed.
///
/// Items whose size could not be measured are shown beside the ring and are
/// excluded from it, because they are unknown rather than zero.
struct StorageSummaryView: View {
    let summaries: [ScanModel.CategorySummary]
    let knownBytes: UInt64
    let unknownCount: Int
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.locale) private var locale

    private var total: Double { max(Double(knownBytes), 1) }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if reduceTransparency {
                    Circle().stroke(.secondary, lineWidth: Layout.ringStroke)
                } else {
                    Circle().stroke(.quaternary, lineWidth: Layout.ringStroke)
                }

                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    Circle()
                        .trim(from: segment.start, to: segment.end)
                        .stroke(
                            Self.color(for: segment.category),
                            style: StrokeStyle(lineWidth: Layout.ringStroke, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                        .accessibilityHidden(true)
                        .zIndex(Double(index))
                }

                VStack(spacing: 2) {
                    Text(ByteLabel.format(knownBytes))
                        .font(.system(size: 38, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("Potential cleanup")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(Layout.ringStroke * 2)
            }
            .frame(
                minWidth: Layout.ringMinimum, maxWidth: Layout.ringMaximum,
                minHeight: Layout.ringMinimum, maxHeight: Layout.ringMaximum
            )
            .help(
                """
                An estimate of the space these items occupy. Moving them to the Trash does not \
                free space until you empty the Trash.
                """
            )
            // A chart must have a textual equivalent. This is it.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Potential cleanup")
            .accessibilityValue(accessibleSummary)
            .accessibilityIdentifier("overview.ring")

            if unknownCount > 0 {
                CountText(
                    "%lld item could not be measured and is not included in this total.",
                    unknownCount
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("overview.unknownSizes")
            }
        }
    }

    private struct Segment {
        let category: CleanupCategory
        let start: Double
        let end: Double
    }

    private var segments: [Segment] {
        var running = 0.0
        return summaries.map { summary in
            let fraction = Double(summary.knownBytes) / total
            let segment = Segment(
                category: summary.category, start: running, end: min(running + fraction, 1))
            running += fraction
            return segment
        }
    }

    private var accessibleSummary: String {
        var parts = [
            LocalizedFormatters.text(
                "%@ of potential cleanup", locale: locale,
                LocalizedFormatters.bytes(knownBytes, locale: locale))
        ]
        parts.append(
            contentsOf: summaries.prefix(5).map {
                LocalizedFormatters.text(
                    "%1$@: %2$@", locale: locale,
                    CategoryNaming.title($0.category),
                    LocalizedFormatters.bytes($0.knownBytes, locale: locale))
            })
        if unknownCount > 0 {
            parts.append(
                LocalizedFormatters.count(
                    "%lld item of unknown size, excluded from the total",
                    unknownCount, locale: locale))
        }
        return parts.joined(separator: ". ")
    }

    /// Category colours, used only alongside a name — never as the sole carrier
    /// of meaning.
    static func color(for category: CleanupCategory) -> Color {
        switch category {
        case .node, .yarn, .pnpm, .bun: return .green
        case .xcode, .simulator: return .blue
        case .flutter: return .purple
        case .docker: return .orange
        case .homebrew: return .gray
        case .gradle: return .teal
        case .python: return .indigo
        case .rust: return .brown
        case .cocoaPods: return .pink
        case .webBuild: return .mint
        case .largeFiles: return .cyan
        }
    }
}

/// Human names and symbols for each category.
enum CategoryNaming {
    static func title(_ category: CleanupCategory) -> String {
        switch category {
        case .node: return String(localized: "Node.js dependencies")
        case .webBuild: return String(localized: "Web build output")
        case .flutter: return String(localized: "Flutter and Dart builds")
        case .xcode: return String(localized: "Xcode data")
        case .simulator: return String(localized: "Simulator caches")
        case .cocoaPods: return String(localized: "CocoaPods cache")
        case .homebrew: return String(localized: "Homebrew cache")
        case .gradle: return String(localized: "Gradle caches")
        case .python: return String(localized: "Python caches")
        case .rust: return String(localized: "Rust caches")
        case .yarn: return String(localized: "Yarn cache")
        case .pnpm: return String(localized: "pnpm store")
        case .bun: return String(localized: "Bun cache")
        case .docker: return String(localized: "Docker resources")
        case .largeFiles: return String(localized: "Large files")
        }
    }

    static func detail(_ category: CleanupCategory) -> String {
        switch category {
        case .node: return String(localized: "Installed packages and package-manager caches")
        case .webBuild: return String(localized: "Generated site output")
        case .flutter: return String(localized: "Build outputs and tool metadata")
        case .xcode: return String(localized: "Derived data, archives and device support")
        case .simulator: return String(localized: "Simulator support caches")
        case .cocoaPods: return String(localized: "Downloaded pod specifications")
        case .homebrew: return String(localized: "Downloaded formulae and bottles")
        case .gradle: return String(localized: "Dependency and build caches")
        case .python: return String(localized: "Downloaded wheels and package caches")
        case .rust: return String(localized: "Crate registry and Git checkouts")
        case .yarn: return String(localized: "Downloaded package archives")
        case .pnpm: return String(localized: "Content-addressed package store")
        case .bun: return String(localized: "Downloaded package cache")
        case .docker: return String(localized: "Images, volumes, containers and build cache")
        case .largeFiles: return String(localized: "Files you selected yourself")
        }
    }

    static func symbol(_ category: CleanupCategory) -> String {
        switch category {
        case .node, .yarn, .pnpm, .bun: return "shippingbox"
        case .webBuild: return "globe"
        case .flutter: return "square.stack.3d.up"
        case .xcode: return "hammer"
        case .simulator: return "iphone"
        case .cocoaPods: return "cube.box"
        case .homebrew: return "cup.and.saucer"
        case .gradle: return "a.square"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .rust: return "gearshape.2"
        case .docker: return "shippingbox.fill"
        case .largeFiles: return "doc"
        }
    }
}
