import Domain
import SwiftUI

/// What MacDevClean has done.
struct HistoryView: View {
    @Bindable var model: HistoryModel
    @State private var expanded: Set<UUID> = []

    var body: some View {
        Group {
            if model.sessions.isEmpty {
                EmptyStateView(
                    symbol: "clock",
                    title: "No cleanups yet",
                    message: """
                        Once MacDevClean moves something, it records what it did here, \
                        and that record survives quitting the app.
                        """
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Layout.cardGap) {
                        ForEach(model.sessions) { session in
                            sessionCard(session)
                        }
                    }
                    .padding(Layout.contentInset)
                }
            }
        }
        .navigationTitle(Text("History"))
        .toolbar {
            ToolbarItem {
                Button("Open Trash") { model.openTrash() }
                    .accessibilityIdentifier("history.openTrash")
            }
            ToolbarItem {
                Button("Clear history…") { model.isConfirmingClear = true }
                    .disabled(model.sessions.isEmpty)
                    .accessibilityIdentifier("history.clear")
            }
        }
        .confirmationDialog(
            "Clear the cleanup history?",
            isPresented: $model.isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear history", role: .destructive) {
                Task { await model.clearConfirmed() }
            }
            .accessibilityIdentifier("history.clear.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                """
                This removes the record of what was done. It does not affect any file, \
                and it does not empty the Trash.
                """
            )
        }
        .task { await model.load() }
    }

    private func sessionCard(_ session: HistorySession) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            session.startedAt,
                            format: .dateTime.year().month().day().hour().minute()
                        )
                        .font(.headline)
                        .monospacedDigit()
                        if session.completedAt == nil {
                            Text("This session did not finish")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if let summary = session.summary {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ByteLabel.format(summary.bytesMovedToTrash) + " moved")
                                .font(.callout)
                                .monospacedDigit()
                            Text("Moved, not freed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 16) {
                    Label(
                        "^[\(model.completedCount(session)) item](inflect: true) done",
                        systemImage: "checkmark")
                    if model.problemCount(session) > 0 {
                        Label(
                            """
                            ^[\(model.problemCount(session)) item](inflect: true) skipped or \
                            failed
                            """,
                            systemImage: "exclamationmark.triangle")
                    }
                    if model.unknownCount(session) > 0 {
                        Label(
                            "^[\(model.unknownCount(session)) outcome](inflect: true) unknown",
                            systemImage: "questionmark.circle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expanded.contains(session.id) },
                        set: { open in
                            if open {
                                expanded.insert(session.id)
                            } else {
                                expanded.remove(session.id)
                            }
                        })
                ) {
                    HistoryDetailView(session: session, model: model)
                } label: {
                    Text("Details").font(.callout)
                }
                .accessibilityIdentifier("history.session.\(session.id.uuidString).details")
            }
        }
    }
}
