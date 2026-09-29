import AppKit
import SwiftUI
import CurrentFeature

@main
struct CurrentApp: App {
    @NSApplicationDelegateAdaptor(CurrentAppDelegate.self) private var appDelegate
    @StateObject private var controller = TimelineController()
    @StateObject private var configurationStore = CurrentConfigurationStore()
    @StateObject private var workspace = WorkspaceViewState()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller, configurationStore: configurationStore, workspace: workspace)
                .onAppear { appDelegate.controller = controller }
        }
        .defaultSize(width: 1180, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CurrentCommands(controller: controller, configurationStore: configurationStore, workspace: workspace)
        }
    }
}

@MainActor
final class CurrentAppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: TimelineController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Streams share one editor workspace and have their own optional tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        guard controller.flushAllSaves() else {
            sender.activate(ignoringOtherApps: true)
            return .terminateCancel
        }
        return .terminateNow
    }
}
