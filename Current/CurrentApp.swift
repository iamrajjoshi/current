import SwiftUI
import CurrentFeature

@main
struct CurrentApp: App {
    @StateObject private var controller = TimelineController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CurrentCommands(controller: controller)
        }
    }
}
