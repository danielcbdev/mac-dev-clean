import SwiftUI

@main
struct MacDevCleanApp: App {
    /// The composition root, built once at launch.
    @State private var coordinator = RootCoordinator(dependencies: AppDependencies.live())

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: coordinator)
                .frame(
                    minWidth: Layout.windowMinimumWidth,
                    idealWidth: Layout.windowDefaultWidth,
                    minHeight: Layout.windowMinimumHeight,
                    idealHeight: Layout.windowDefaultHeight
                )
        }
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: Layout.windowDefaultWidth,
            height: Layout.windowDefaultHeight
        )
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
