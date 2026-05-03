import AppKit
import SwiftUI
import CurrentFeature

@main
struct CurrentApp: App {
    @StateObject private var controller = TimelineController()
    @StateObject private var configurationStore = CurrentConfigurationStore()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller, configurationStore: configurationStore)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CurrentCommands(controller: controller, configurationStore: configurationStore)
        }
    }
}
