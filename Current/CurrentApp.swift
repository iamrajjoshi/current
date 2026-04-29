import AppKit
import SwiftUI
import CurrentFeature

@main
struct CurrentApp: App {
    @StateObject private var controller = TimelineController()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CurrentCommands(controller: controller)
        }
    }
}
