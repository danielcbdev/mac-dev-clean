import Domain
import SwiftUI

/// Large Files: an analysis tool, and never a list of things to delete.
struct LargeFilesView: View {
    @Bindable var coordinator: RootCoordinator
    @Bindable var model: LargeFilesModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .navigationTitle(Text("Large Files"))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button("Choose folders…") {
                Task { await model.chooseAndScan() }
            }
            .disabled(model.isScanning)
            .accessibilityIdentifier("largeFiles.choose")

            Picker("Smallest size", selection: $model.minimumBytes) {
                ForEach(LargeFileThreshold.presets, id: \.self) { value in
                    Text(ByteLabel.format(value)).tag(value)
                }
            }
            .frame(maxWidth: 190)
            .disabled(model.isScanning)
            .accessibilityIdentifier("largeFiles.threshold")

            Picker("Sort", selection: $model.sort) {
                Text("Largest first").tag(LargeFilesModel.Sort.size)
                Text("Oldest first").tag(LargeFilesModel.Sort.age)
                Text("By name").tag(LargeFilesModel.Sort.name)
                Text("By location").tag(LargeFilesModel.Sort.location)
            }
            .frame(maxWidth: 180)
            .accessibilityIdentifier("largeFiles.sort")

            Spacer()

            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("largeFiles.progress")
                Button("Stop") { model.cancel() }
                    .accessibilityIdentifier("largeFiles.cancel")
            } else if !model.chosenFolders.isEmpty {
                Button("Scan again") { model.start() }
                    .accessibilityIdentifier("largeFiles.rescan")
            }
        }
        .padding(.horizontal, Layout.contentInset)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.chosenFolders.isEmpty {
            EmptyStateView(
                symbol: "folder.badge.questionmark",
                title: "Choose a folder to look inside",
                message: """
                    MacDevClean looks only where you point it. Broad locations such as your \
                    home folder, /Users or /Applications are refused: pick something specific.
                    """,
                actionTitle: "Choose folders…",
                action: { Task { await model.chooseAndScan() } }
            )
            Spacer()
        } else if model.rows.isEmpty && !model.isScanning {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: "Nothing that big",
                message: "No file in the folders you chose reaches the size you set."
            )
            Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.visibleRows) { row in
                        if row.id != model.visibleRows.first?.id { Divider() }
                        LargeFileRowView(
                            row: row,
                            isSelected: model.isSelected(row.id),
                            onToggle: { model.toggle(row) },
                            onReveal: { model.reveal(id: row.id) }
                        )
                    }
                }
                .padding(.horizontal, Layout.contentInset)
                .accessibilityIdentifier("largeFiles.results")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("^[\(model.selectedIDs.count) file](inflect: true) selected")
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .accessibilityIdentifier("largeFiles.selectionCount")
                Text(
                    """
                    Large files are not necessarily disposable. Review their contents before \
                    moving them to the Trash.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if model.informationalRowCount > 0 {
                    Text(
                        """
                        ^[\(model.informationalRowCount) row](inflect: true) shown for \
                        information only and cannot be selected.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                ByteLabel(bytes: model.selectedBytes, style: .body.weight(.medium))
                Button {
                    if let snapshot = model.snapshot {
                        coordinator.review(scanID: snapshot.id, ids: model.selectedIDs)
                    }
                } label: {
                    Text("Review ^[\(model.selectedIDs.count) selected file](inflect: true)")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedIDs.isEmpty || model.isScanning)
                .accessibilityIdentifier("largeFiles.review")
            }
        }
        .padding(.horizontal, Layout.contentInset)
        .padding(.vertical, 14)
    }
}
