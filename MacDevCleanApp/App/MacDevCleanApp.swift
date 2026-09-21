import SwiftUI

@main
struct MacDevCleanApp: App {
    // The composition root is built once, at launch. Nothing reads it yet:
    // the feature models that receive it arrive with the app shell in plan
    // 05. Constructing it here keeps that wiring in one place from the start.
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
