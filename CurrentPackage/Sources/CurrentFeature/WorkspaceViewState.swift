import AppKit
import Combine
import SwiftUI

public enum WorkspaceAppearance: String, CaseIterable {
    case system, light, dark

    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum WorkspaceSheet: Identifiable {
    case search, commands, switcher, tabSwitcher, newStream(UUID?), renameStream(Stream), newFolder, renameFolder(StreamFolder), conflict(DocumentConflict)

    var id: String {
        switch self {
        case .search: "search"
        case .commands: "commands"
        case .switcher: "switcher"
        case .tabSwitcher: "tab-switcher"
        case .newStream: "new-stream"
        case .renameStream(let stream): "rename-\(stream.id)"
        case .newFolder: "new-folder"
        case .renameFolder(let folder): "rename-\(folder.id)"
        case .conflict(let conflict): "conflict-\(conflict.id)"
        }
    }
}

@MainActor
public final class WorkspaceViewState: ObservableObject {
    @Published public var sidebarVisible: Bool {
        didSet { defaults.set(sidebarVisible, forKey: "workspace.sidebarVisible") }
    }
    @Published public var showsTabs: Bool {
        didSet { defaults.set(showsTabs, forKey: "workspace.showsTabs") }
    }
    @Published public var appearance: WorkspaceAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "workspace.appearance") }
    }
    @Published public var sourceMode: Bool {
        didSet { defaults.set(sourceMode, forKey: "workspace.sourceMode") }
    }
    @Published public var focusMode: Bool {
        didSet { defaults.set(focusMode, forKey: "workspace.focusMode") }
    }
    @Published var sidebarWidth: Double {
        didSet { defaults.set(sidebarWidth, forKey: "workspace.sidebarWidth") }
    }
    @Published var collapsedFolders: Set<UUID> {
        didSet { defaults.set(collapsedFolders.map(\.uuidString), forKey: "workspace.collapsedFolders") }
    }
    @Published var sheet: WorkspaceSheet?
    @Published var showsDatePicker = false
    @Published var selectedDate = Date()
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sidebarVisible = defaults.object(forKey: "workspace.sidebarVisible") as? Bool ?? true
        self.showsTabs = defaults.bool(forKey: "workspace.showsTabs")
        self.sourceMode = defaults.bool(forKey: "workspace.sourceMode")
        self.focusMode = defaults.bool(forKey: "workspace.focusMode")
        self.appearance = WorkspaceAppearance(rawValue: defaults.string(forKey: "workspace.appearance") ?? "system") ?? .system
        self.sidebarWidth = min(320, max(200, defaults.object(forKey: "workspace.sidebarWidth") as? Double ?? 212))
        self.collapsedFolders = Set((defaults.stringArray(forKey: "workspace.collapsedFolders") ?? []).compactMap(UUID.init(uuidString:)))
    }
}

struct WorkspaceIconButton: View {
    let title: String
    let symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Neutral hover and pressed feedback without moving the writing surface.
struct WorkspaceControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Control(configuration: configuration)
    }

    private struct Control: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background(
                    CurrentTheme.fieldBackground.opacity(configuration.isPressed ? 1 : hovered ? 0.7 : 0),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .onHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        }
    }
}
