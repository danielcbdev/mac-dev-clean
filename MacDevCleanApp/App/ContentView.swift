import SwiftUI

/// The window: a sidebar of destinations beside the active screen.
struct ContentView: View {
    @Bindable var coordinator: RootCoordinator

    /// Pinned open. The sidebar is the only way between screens, so a state
    /// where it is gone is a state the user cannot leave.
    ///
    /// Unverified as a fix: the column was never observed collapsed, only
    /// empty, so this closes a door that was not the one standing open.
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if coordinator.state == .onboarding {
                OnboardingView(model: coordinator.rootSelection) {
                    Task { await coordinator.confirmRoots() }
                }
                .frame(
                    minWidth: Layout.windowMinimumWidth,
                    minHeight: Layout.windowMinimumHeight
                )
            } else {
                NavigationSplitView(columnVisibility: $columns) {
                    sidebar
                } detail: {
                    detail
                }
                .navigationSplitViewStyle(.balanced)
                .frame(
                    minWidth: Layout.windowMinimumWidth,
                    minHeight: Layout.windowMinimumHeight
                )
            }
        }
        .environment(\.locale, coordinator.interfaceLocale)
        .task { await coordinator.load() }
    }

    // MARK: - Sidebar

    /// The `List` is the column itself, and the wordmark and the reassurance
    /// ride on it as safe-area insets.
    ///
    /// This is the canonical macOS construction, adopted while investigating
    /// D3. It is **not** a fix for D3: the sidebar still empties on the
    /// screens the owner reported, and bisection showed the cause is in the
    /// detail screens' own content, not in this column. The previous form — a
    /// `VStack` wrapping the `List` — was ruled out as the cause and replaced
    /// anyway, because a `List` with no definite height in a split-view column
    /// is worth not having while the real cause is still open. See
    /// docs/verification/10-defects.md for what was measured and what is
    /// still unexplained.
    private var sidebar: some View {
        List(Destination.sidebarItems, id: \.self, selection: $coordinator.destination) {
            destination in
            let isActive = destination == coordinator.destination
            // macOS forces a selected sidebar row's SF Symbol to white,
            // ignoring `.foregroundStyle`/`.symbolRenderingMode` applied to
            // a `Label` as a whole. Styling the icon `Image` directly,
            // separately from the text, is what actually survives that.
            Label {
                Text(destination.title)
                    .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                    .fontWeight(isActive ? .bold : .regular)
            } icon: {
                Image(systemName: destination.symbol)
                    .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
            }
            .accessibilityIdentifier(destination.accessibilityID)
            .listRowBackground(
                RoundedRectangle(cornerRadius: Layout.controlRadius)
                    .fill(isActive ? Theme.accentSoft : Color.clear)
                    .padding(.vertical, 2)
            )
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebarBackground)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MacDevClean")
                    .appFont(Typography.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)
                Text("Understand it before you remove it.")
                    .appFont(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Layout.space12)
            .padding(.top, Layout.space12)
            .padding(.bottom, Layout.space8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Label("Nothing is removed until you confirm.", systemImage: "hand.raised")
                .appFont(Typography.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(Layout.space12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationSplitViewColumnWidth(
            min: Layout.sidebarMinimum,
            ideal: Layout.sidebarIdeal,
            max: Layout.sidebarMaximum
        )
    }

    // MARK: - Detail

    /// Routing reads the destination's `screenKind` rather than the
    /// destination itself. The distinction matters: a `switch` on the
    /// destination is what let Large Files keep claiming it did not exist for
    /// four milestones after it was built, because nothing could assert
    /// against a branch inside a view body. `NavigationTests` asserts against
    /// `screenKind`.
    @ViewBuilder
    private var detail: some View {
        if coordinator.isReviewing {
            ReviewView(
                coordinator: coordinator,
                model: coordinator.scanModel,
                review: coordinator.reviewModel
            )
        } else {
            switch coordinator.destination.screenKind {
            case .overview:
                OverviewView(coordinator: coordinator, model: coordinator.scanModel)
            case .caches:
                CachesView(coordinator: coordinator, model: coordinator.scanModel)
            case .largeFiles:
                LargeFilesView(coordinator: coordinator, model: coordinator.largeFiles)
            case .history:
                HistoryView(model: coordinator.history)
            case .exclusions:
                ExclusionsView(model: coordinator.exclusionsModel)
            case .settings:
                SettingsView(
                    model: coordinator.settings,
                    cleanupEnabled: coordinator.dependencies.cleanupEnabled
                )
            case .placeholder:
                // Unreachable: `sidebarItems` does not offer a destination
                // without a screen, so one can never be selected. Rendering
                // nothing is the honest fallback — the previous code rendered
                // a message saying a finished feature did not exist.
                EmptyView()
            }
        }
    }
}
