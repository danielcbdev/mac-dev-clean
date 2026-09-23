import Domain
import SwiftUI

/// Project roots, behaviour, appearance and what the app keeps.
struct SettingsView: View {
    @Bindable var model: SettingsModel
    let cleanupEnabled: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.cardGap) {
                rootsCard
                behaviourCard
                appearanceCard
                aboutCard
            }
            .padding(Layout.contentInset)
        }
        .navigationTitle(Text("Settings"))
        .task { await model.load() }
    }

    private var rootsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Project folders").font(.headline)
                Text("MacDevClean looks for project artifacts only inside these folders.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(model.roots, id: \.url) { root in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(root.url.lastPathComponent).font(.body)
                            Text(root.url.deletingLastPathComponent().lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove") { Task { await model.remove(root) } }
                            .accessibilityIdentifier(
                                "settings.root.\(root.url.lastPathComponent).remove")
                    }
                    .padding(.vertical, 4)
                }

                Button("Add a folder…") { Task { await model.addRoots() } }
                    .accessibilityIdentifier("settings.addRoot")
            }
        }
    }

    private var behaviourCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Behaviour").font(.headline)

                Toggle(isOn: $model.preferences.scanOnLaunch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan when MacDevClean opens")
                        Text("Off by default. Scanning still never removes anything.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(!model.canEnableScanOnLaunch)
                .accessibilityIdentifier("settings.scanOnLaunch")
                .onChange(of: model.preferences.scanOnLaunch) { _, _ in
                    Task { await model.savePreferences() }
                }

                Picker("Large file size", selection: $model.preferences.largeFileThreshold) {
                    ForEach(LargeFileThreshold.presets, id: \.self) { value in
                        Text(ByteLabel.format(value)).tag(value)
                    }
                }
                .accessibilityIdentifier("settings.threshold")
                .onChange(of: model.preferences.largeFileThreshold) { _, _ in
                    Task { await model.savePreferences() }
                }

                Picker("Keep history", selection: $model.preferences.retention) {
                    Text("Forever").tag(HistoryRetention.forever)
                    Text("30 days").tag(HistoryRetention.days30)
                    Text("90 days").tag(HistoryRetention.days90)
                }
                .accessibilityIdentifier("settings.retention")
                .onChange(of: model.preferences.retention) { _, _ in
                    Task { await model.savePreferences() }
                }

                if !cleanupEnabled {
                    Label(
                        """
                        Cleanup is unavailable because MacDevClean cannot record what it did. \
                        Scanning and explaining still work.
                        """,
                        systemImage: "lock"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.cleanupUnavailable")
                }
            }
        }
    }

    private var appearanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance and language").font(.headline)

                Picker("Language", selection: $model.preferences.language) {
                    Text("System").tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("Português (Brasil)").tag(AppLanguage.portugueseBrazil)
                }
                .accessibilityIdentifier("settings.language")
                .onChange(of: model.preferences.language) { _, _ in
                    Task { await model.savePreferences() }
                }

                Picker("Appearance", selection: $model.preferences.appearance) {
                    Text("System").tag(AppAppearance.system)
                    Text("Light").tag(AppAppearance.light)
                    Text("Dark").tag(AppAppearance.dark)
                }
                .accessibilityIdentifier("settings.appearance")
                .onChange(of: model.preferences.appearance) { _, _ in
                    Task { await model.savePreferences() }
                }
            }
        }
    }

    private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("About").font(.headline)
                LabeledContent("Version", value: Self.version)
                Text(
                    """
                    Everything stays on this Mac. MacDevClean has no accounts, no analytics \
                    and no server, and it needs no network access to scan or clean.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.privacy")
            }
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
    }
}
