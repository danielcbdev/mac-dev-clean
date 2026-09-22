import SwiftUI

/// The window: a sidebar of destinations beside the active screen.
struct ContentView: View {
    @Bindable var coordinator: RootCoordinator

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
                NavigationSplitView {
                    sidebar
                } detail: {
                    detail
                }
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MacDevClean")
                    .font(.title2.weight(.semibold))
                Text("Understand it before you remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            List(selection: $coordinator.destination) {
                ForEach(Destination.allCases) { destination in
                    Label(destination.title, systemImage: destination.symbol)
                        .tag(destination)
                        .accessibilityIdentifier(destination.accessibilityID)
                }
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)

            Label("Nothing is removed until you confirm.", systemImage: "hand.raised")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .navigationSplitViewColumnWidth(
            min: Layout.sidebarMinimum,
            ideal: Layout.sidebarIdeal,
            max: Layout.sidebarMaximum
        )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if coordinator.isReviewing {
            ReviewView(
                coordinator: coordinator,
                model: coordinator.scanModel,
                review: coordinator.reviewModel
            )
        } else {
            switch coordinator.destination {
            case .overview:
                OverviewView(coordinator: coordinator, model: coordinator.scanModel)
            case .caches:
                CachesView(coordinator: coordinator, model: coordinator.scanModel)
            case .largeFiles:
                UpcomingFeatureView(
                    destination: .largeFiles,
                    symbol: "folder",
                    title: "Large Files is not built yet",
                    message:
                        """
                        This will let you pick a folder and look at what is big inside it. It \
                        analyses only folders you choose, and nothing is ever preselected.
                        """
                )
            case .history:
                HistoryView(model: coordinator.history)
            case .exclusions:
                ExclusionsView(model: coordinator.exclusionsModel)
            case .settings:
                SettingsView(
                    model: coordinator.settings,
                    cleanupEnabled: coordinator.dependencies.cleanupEnabled
                )
            }
        }
    }
}
