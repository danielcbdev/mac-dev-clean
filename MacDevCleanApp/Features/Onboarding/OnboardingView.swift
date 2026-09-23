import SwiftUI

/// First run. Nothing is scanned until the user accepts a scope.
struct OnboardingView: View {
    @Bindable var model: RootSelectionModel
    let onConfirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.cardGap) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose what MacDevClean may look at")
                        .font(.largeTitle.weight(.semibold))
                    Text(
                        """
                        MacDevClean only scans folders you add here. It never looks anywhere \
                        else, and it scans nothing until you say so.
                        """
                    )
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Project folders").font(.headline)
                        if model.proposals.isEmpty {
                            Text(
                                """
                                No conventional project folders were found in your home \
                                folder. Add one to continue.
                                """
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        ForEach(model.proposals, id: \.self) { url in
                            Toggle(isOn: binding(for: url)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent).font(.body)
                                    Text("in your home folder")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier("roots.proposal.\(url.lastPathComponent)")
                        }

                        HStack {
                            Button("Add a folder…") {
                                Task { await model.addFolders() }
                            }
                            .accessibilityIdentifier("roots.choose")

                            Spacer()

                            Button("Start with these folders") {
                                onConfirm()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canConfirm)
                            .accessibilityIdentifier("roots.confirm")
                        }
                        .padding(.top, 4)
                    }
                }

                InfoCard(
                    symbol: "hand.raised",
                    tint: .blue,
                    title: "You stay in control",
                    message:
                        """
                        Nothing is scanned, selected or removed without you asking. You can \
                        change these folders at any time in Settings.
                        """
                )
            }
            .padding(Layout.contentInset)
        }
        .onAppear { model.loadProposals() }
    }

    private func binding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { model.chosen.contains(url) },
            set: { _ in model.toggle(url) }
        )
    }
}
