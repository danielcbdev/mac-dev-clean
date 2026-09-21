import Domain
import SwiftUI

/// The selectable list. This is where a cleanup is assembled.
struct CachesView: View {
    @Bindable var coordinator: RootCoordinator
    /// Bound separately: the coordinator holds its models as constants, and a
    /// binding has to reach the observable object itself.
    @Bindable var model: ScanModel

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

            if model.candidates.isEmpty {
                EmptyStateView(
                    symbol: "tray",
                    title: model.hasScanned ? "Nothing found" : "No results yet",
                    message: model.hasScanned
                        ? "MacDevClean found no removable artifacts in the folders you added."
                        : "Run a scan from the Overview to see what is taking up space.",
                    actionTitle: model.hasScanned ? nil : "Start scan",
                    action: model.hasScanned ? nil : { coordinator.startScan() }
                )
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

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Ecosystem", selection: $model.ecosystemFilter) {
                Text("All ecosystems").tag(CleanupCategory?.none)
                ForEach(availableCategories, id: \.self) { category in
                    Text(CategoryNaming.title(category)).tag(CleanupCategory?.some(category))
                }
            }
            .frame(maxWidth: 260)
            .accessibilityIdentifier("filter.ecosystem")

            Picker("Risk", selection: $model.riskFilter) {
                Text("Any risk").tag(RiskLevel?.none)
                ForEach(RiskLevel.allCases, id: \.self) { risk in
                    Text(RiskBadge.title(risk)).tag(RiskLevel?.some(risk))
                }
            }
            .frame(maxWidth: 180)
            .accessibilityIdentifier("filter.risk")

            Picker("Sort", selection: $model.sort) {
                Text("Largest first").tag(ScanModel.Sort.size)
                Text("By name").tag(ScanModel.Sort.name)
            }
            .frame(maxWidth: 170)
            .accessibilityIdentifier("filter.sort")

            Spacer()

            Button("Select all low and medium risk") { model.selectAllSelectable() }
                .accessibilityIdentifier("selection.selectAll")
            Button("Clear selection") { model.clearSelection() }
                .disabled(model.selectedIDs.isEmpty)
                .accessibilityIdentifier("selection.clear")
        }
        .padding(.horizontal, Layout.contentInset)
        .padding(.vertical, 12)
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
                    systemImage: "exclamationmark.octagon"
                )
                .font(.headline)
                .foregroundStyle(.red)

                Text(
                    """
                    These may hold data that exists nowhere else. Nothing here is selected for \
                    you, and bulk selection never touches it.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                            Text(CategoryNaming.title(category)).font(.body.weight(.medium))
                            Spacer()
                            Text(
                                """
                                ^[\(highRisk.filter { $0.category == category }.count) \
                                item](inflect: true)
                                """
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                Text("^[\(model.selectedIDs.count) item](inflect: true) selected")
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .accessibilityIdentifier("selection.count")
                Text(
                    "About " + ByteLabel.format(model.selectedKnownBytes)
                        + " will move to the Trash. That frees space only when you empty it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                coordinator.openReview()
            } label: {
                Text("Review \(model.selectedIDs.count) selected")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selectedIDs.isEmpty)
            .accessibilityIdentifier("cleanup.review")
        }
        .padding(.horizontal, Layout.contentInset)
        .padding(.vertical, 14)
    }
}
