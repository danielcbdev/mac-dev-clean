import Domain
import SwiftUI

/// Everything MacDevClean has been told to leave alone.
struct ExclusionsView: View {
    @Bindable var model: ExclusionsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Exclude a folder…") { Task { await model.addPaths() } }
                    .accessibilityIdentifier("exclusions.addPath")

                Menu("Exclude a category") {
                    ForEach(CleanupCategory.allCases, id: \.self) { category in
                        Button(CategoryNaming.title(category)) {
                            Task { await model.add(.category(category)) }
                        }
                    }
                }
                .frame(maxWidth: 200)
                .accessibilityIdentifier("exclusions.addCategory")

                Menu("Exclude a rule") {
                    ForEach(Array(projectRuleIDs).sorted(), id: \.self) { rule in
                        Button(rule) { Task { await model.add(.rule(rule)) } }
                    }
                }
                .frame(maxWidth: 180)
                .accessibilityIdentifier("exclusions.addRule")

                Spacer()
            }
            .padding(.horizontal, Layout.contentInset)
            .padding(.vertical, 12)

            Divider()

            if model.exclusions.isEmpty {
                EmptyStateView(
                    symbol: "hand.raised",
                    title: "Nothing is excluded",
                    message: """
                        Add a folder, a category or a rule here and MacDevClean will never \
                        offer it again. You can also exclude an item from its context menu \
                        in Caches.
                        """
                )
                Spacer()
            } else {
                ScrollView {
                    Card {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(model.exclusions.enumerated()), id: \.offset) {
                                _, exclusion in
                                row(exclusion)
                            }
                        }
                    }
                    .padding(Layout.contentInset)
                }
            }
        }
        .navigationTitle(Text("Exclusions"))
        .task { await model.load() }
    }

    private func row(_ exclusion: Exclusion) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title(for: exclusion)).font(.body)
                Text(model.detail(for: exclusion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.resolves(exclusion) {
                    // Kept rather than removed: it is the user's decision, and
                    // the folder may come back.
                    Label(
                        "Unavailable — this location is not there right now",
                        systemImage: "questionmark.folder"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button("Remove") { Task { await model.remove(exclusion) } }
                .accessibilityIdentifier("\(model.identifier(for: exclusion)).remove")
        }
        .padding(.vertical, 10)
        .frame(minHeight: Layout.rowMinimumHeight)
        .accessibilityIdentifier(model.identifier(for: exclusion))
    }
}
