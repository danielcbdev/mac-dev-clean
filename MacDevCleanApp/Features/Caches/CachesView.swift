import Domain
import SwiftUI

/// The selectable list. This is where a cleanup is assembled.
struct CachesView: View {
    @Bindable var coordinator: RootCoordinator
    /// Bound separately: the coordinator holds its models as constants, and a
    /// binding has to reach the observable object itself.
    @Bindable var model: ScanModel

    @Environment(\.locale) private var locale

    private var ordinary: [CleanupCandidate] {
        model.visibleCandidates.filter { $0.risk != .high }
    }
    private var highRisk: [CleanupCandidate] {
        model.visibleCandidates.filter { $0.risk == .high }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if model.isScanning {
                scanningState
                Spacer()
            } else if model.hasResultsHiddenByFilters {
                // A filter that matches nothing is not an empty result. The
                // screen used to render an empty scroll area with no message
                // at all, which reads as "you have nothing".
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "The filters hide every result",
                    message: """
                        A scan found things here. Nothing matches the filters you set, \
                        and clearing them brings the results back.
                        """,
                    actionTitle: "Clear filters",
                    action: { model.clearFilters() }
                )
                Spacer()
            } else if model.candidates.isEmpty {
                emptyState
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Layout.cardGap) {
                        if !ordinary.isEmpty {
                            Card {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(ordinary) { candidate in
                                        if candidate.id != ordinary.first?.id { Divider() }
                                        row(for: candidate)
                                    }
                                }
                            }
                        }
                        if !highRisk.isEmpty { highRiskSection }
                    }
                    .padding(Layout.contentInset)
                }
            }

            Divider()
            footer
        }
        .navigationTitle(Text("Caches"))
    }

    // MARK: - Toolbar

    /// Wraps to a second row rather than overflowing.
    ///
    /// This was one `HStack` holding three pickers capped at 260, 180 and 170
    /// points, a bulk-selection button and a clear button, with nothing that
    /// could break the line. At the 1100 pt window minimum it did not merely
    /// clip: the row forced the whole screen past the window's height, and the
    /// controls were laid out 128 points *above* the top edge while the footer
    /// sat below the bottom one. Brazilian Portuguese labels are longer than
    /// the English ones, so no fixed width assumption survives either.
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                filters
                Spacer(minLength: 12)
                selectionButtons
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    filters
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    selectionButtons
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Layout.contentInset)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var filters: some View {
        Group {
            labeledFilter("Ecosystem") {
                Picker("Ecosystem", selection: $model.ecosystemFilter) {
                    Text("All ecosystems").tag(CleanupCategory?.none)
                    ForEach(availableCategories, id: \.self) { category in
                        Text(CategoryNaming.title(category)).tag(CleanupCategory?.some(category))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
                .accessibilityIdentifier("filter.ecosystem")
            }

            labeledFilter("Risk") {
                Picker("Risk", selection: $model.riskFilter) {
                    Text("Any risk").tag(RiskLevel?.none)
                    ForEach(RiskLevel.allCases, id: \.self) { risk in
                        Text(RiskBadge.title(risk)).tag(RiskLevel?.some(risk))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
                .accessibilityIdentifier("filter.risk")
            }

            labeledFilter("Sort") {
                Picker("Sort", selection: $model.sort) {
                    Text("Largest first").tag(ScanModel.Sort.size)
                    Text("By name").tag(ScanModel.Sort.name)
                }
                .labelsHidden()
                .frame(maxWidth: 170)
                .accessibilityIdentifier("filter.sort")
            }
        }
    }

    private func labeledFilter<Content: View>(
        _ label: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .appFont(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }

    @ViewBuilder
    private var selectionButtons: some View {
        Button("Select all low and medium risk") { model.selectAllSelectable() }
            .buttonStyle(.macDevSecondary)
            .accessibilityIdentifier("selection.selectAll")
        Button("Clear selection") { model.clearSelection() }
            .buttonStyle(.macDevSecondary)
            .disabled(model.selectedIDs.isEmpty)
            .accessibilityIdentifier("selection.clear")
    }

    // MARK: - States

    /// A user who presses Start must see that something started.
    private var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .accessibilityHidden(true)
            Text("Scanning")
                .appFont(Typography.title)
                .foregroundStyle(Theme.textPrimary)
            CountText("Looking through your folders. %lld entries so far.", model.visited)
                .appFont(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .accessibilityIdentifier("caches.scanProgress")
            Button("Stop scanning") { coordinator.cancelScan() }
                .buttonStyle(.macDevSecondary)
                .accessibilityIdentifier("caches.cancelScan")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    /// Nothing was found, or nothing has been scanned yet. When a scan cannot
    /// start, the control that would start it is disabled and the reason is
    /// stated beneath it — an enabled control that does nothing is not honest.
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            EmptyStateView(
                symbol: "tray",
                title: model.hasScanned ? "Nothing found" : "No results yet",
                message: model.hasScanned
                    ? "MacDevClean found no removable artifacts in the folders you added."
                    : "Run a scan from the Overview to see what is taking up space."
            )

            if !model.hasScanned {
                Button("Start scan") { coordinator.startScan() }
                    .buttonStyle(.macDevPrimary)
                    .disabled(coordinator.scanUnavailableReason != nil)
                    .accessibilityIdentifier("caches.startScan")

                if let reason = coordinator.scanUnavailableReason {
                    VStack(spacing: 6) {
                        Text(Self.explanation(for: reason))
                            .appFont(Typography.body)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("caches.scanUnavailable")

                        if reason == .noRoots {
                            Button("Add folders in Settings") {
                                coordinator.destination = .settings
                            }
                            .buttonStyle(.macDevSecondary)
                            .accessibilityIdentifier("caches.addFolders")
                        }
                    }
                    .frame(maxWidth: 420)
                }
            }
        }
    }

    private static func explanation(for reason: ScanUnavailableReason) -> LocalizedStringKey {
        switch reason {
        case .noRoots:
            return "MacDevClean has no folders to look through yet. Add one and the scan can run."
        case .alreadyScanning:
            return "A scan is already running."
        }
    }

    private var availableCategories: [CleanupCategory] {
        Array(Set(model.candidates.map(\.category)))
            .sorted { CategoryNaming.title($0) < CategoryNaming.title($1) }
    }

    // MARK: - Rows

    private func row(for candidate: CleanupCandidate) -> some View {
        CandidateRow(
            candidate: candidate,
            isSelected: model.isSelected(candidate.id),
            isSelectable: model.canSelectFromList(candidate),
            onToggle: { model.toggle(candidate) },
            onReveal: {
                if case .file(let url) = candidate.location { coordinator.reveal(url) }
            },
            onExclude: {
                Task {
                    if case .file(let url) = candidate.location {
                        await coordinator.exclude(.path(url))
                    }
                }
            }
        )
    }

    /// High-risk items live behind a disclosure the user opens on purpose.
    private var highRiskSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "High risk — open to review individually",
                    systemImage: "exclamationmark.circle"
                )
                .appFont(Typography.title)
                .foregroundStyle(Theme.danger)

                Text(
                    """
                    These may hold data that exists nowhere else. Nothing here is selected for \
                    you, and bulk selection never touches it.
                    """
                )
                .appFont(Typography.body)
                .foregroundStyle(Theme.textSecondary)
                // No fixedSize here: it proposes nil width, the text reports its full
                // unwrapped ideal width, and in a VStack-rooted screen that ballooned the
                // split view and emptied the sidebar. See EmptyStateView.

                ForEach(highRiskCategories, id: \.self) { category in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { model.expandedHighRisk.contains(category) },
                            set: { expanded in
                                if expanded {
                                    model.expandedHighRisk.insert(category)
                                } else {
                                    model.expandedHighRisk.remove(category)
                                    // Closing the section drops its selections:
                                    // the deliberate choice was made inside it.
                                    for item in highRisk where item.category == category {
                                        model.selectedIDs.remove(item.id)
                                    }
                                }
                            }
                        )
                    ) {
                        ForEach(highRisk.filter { $0.category == category }) { candidate in
                            CandidateRow(
                                candidate: candidate,
                                isSelected: model.isSelected(candidate.id),
                                // Selectable only once the section is open.
                                isSelectable: model.expandedHighRisk.contains(category),
                                onToggle: { model.toggle(candidate) },
                                onReveal: {
                                    if case .file(let url) = candidate.location {
                                        coordinator.reveal(url)
                                    }
                                }
                            )
                            .accessibilityIdentifier(
                                "\(highRiskIdentifier(candidate)).select")
                        }
                    } label: {
                        HStack {
                            Text(CategoryNaming.title(category))
                                .appFont(Typography.body)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            CountText(
                                "%lld item",
                                highRisk.filter { $0.category == category }.count
                            )
                            .appFont(Typography.caption)
                            .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .accessibilityIdentifier(Self.disclosureIdentifier(for: category, in: highRisk))
                }
            }
        }
    }

    /// Names the Docker disclosure after the kind of resource it holds, so
    /// automation and VoiceOver can address "the Docker volumes" directly
    /// rather than a generic category.
    static func disclosureIdentifier(
        for category: CleanupCategory,
        in items: [CleanupCandidate]
    ) -> String {
        guard category == .docker else { return "highRisk.\(category.rawValue).details" }
        let kinds = Set(
            items.filter { $0.category == .docker }.compactMap { candidate -> String? in
                if case .docker(_, _, let kind, _) = candidate.location { return kind.rawValue }
                return nil
            })
        guard kinds.count == 1, let kind = kinds.first else { return "highRisk.docker.details" }
        return "docker.\(kind).details"
    }

    private var highRiskCategories: [CleanupCategory] {
        Array(Set(highRisk.map(\.category)))
            .sorted { CategoryNaming.title($0) < CategoryNaming.title($1) }
    }

    /// Docker rows get an identifier naming the resource kind, so automation
    /// can address "the Docker volume" without knowing its name.
    private func highRiskIdentifier(_ candidate: CleanupCandidate) -> String {
        if case .docker(_, _, let kind, _) = candidate.location {
            return "docker.\(kind.rawValue)"
        }
        return "candidate.\(candidate.ruleID)"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                CountText("%lld item selected", model.selectedIDs.count)
                    .appFont(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .accessibilityIdentifier("selection.count")
                Text(
                    LocalizedFormatters.text(
                        """
                        About %@ will move to the Trash. That frees space only when you \
                        empty it.
                        """,
                        locale: locale,
                        LocalizedFormatters.bytes(model.selectedKnownBytes, locale: locale))
                )
                .appFont(Typography.caption)
                .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button {
                coordinator.openReview()
            } label: {
                CountText("Review %lld selected", model.selectedIDs.count)
            }
            .buttonStyle(.macDevPrimary)
            .disabled(model.selectedIDs.isEmpty)
            .accessibilityIdentifier("cleanup.review")
        }
        .padding(.horizontal, Layout.contentInset)
        .padding(.vertical, 14)
        .background(Theme.sidebarBackground)
    }
}
