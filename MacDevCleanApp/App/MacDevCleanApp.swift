import SwiftUI

@main
struct MacDevCleanApp: App {
    private let dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            Text("MacDevClean")
                .accessibilityIdentifier("app.title")
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
    }
}
