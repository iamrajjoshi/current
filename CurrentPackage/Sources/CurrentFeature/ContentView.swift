import AppKit
import Combine
import SwiftUI

public struct ContentView: View {
    @ObservedObject private var controller: TimelineController
    @ObservedObject private var configurationStore: CurrentConfigurationStore
    @ObservedObject private var workspace: WorkspaceViewState
    @State private var initialSidebarWidth: Double
    private let maintenanceTimer = Timer.publish(every: 45, on: .main, in: .common).autoconnect()

    public init(
        controller: TimelineController,
        configurationStore: CurrentConfigurationStore = CurrentConfigurationStore(),
        workspace: WorkspaceViewState = WorkspaceViewState()
    ) {
        self.controller = controller
        self.configurationStore = configurationStore
        self.workspace = workspace
        _initialSidebarWidth = State(initialValue: workspace.sidebarWidth)
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            WorkspaceSidebar(controller: controller, workspace: workspace)
                .onGeometryChange(for: Double.self) { geometry in
                    Double(geometry.size.width.rounded())
                } action: { width in
                    guard workspace.sidebarVisible, !workspace.focusMode, width >= 200,
                          abs(width - workspace.sidebarWidth) > 1 else { return }
                    workspace.sidebarWidth = min(320, width)
                }
                // Keep the sizing preference outside the geometry observer.
                .navigationSplitViewColumnWidth(min: 200, ideal: initialSidebarWidth, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if workspace.showsTabs && !workspace.focusMode { tabs }
                if let conflict = controller.conflicts.first {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.doc")
                        Text("A note changed outside Current. Your edits are still here.")
                        Spacer()
                        Button("Review versions") { workspace.sheet = .conflict(conflict) }
                    }
                    .font(.callout)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(CurrentTheme.accentSoft)
                }
                timeline
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CurrentTheme.pageBackground)
            .overlay(alignment: .topTrailing) {
                if workspace.focusMode {
                    leaveFocusButton.padding(12)
                }
            }
            .toolbar { workspaceToolbar }
            .toolbar(workspace.focusMode ? .hidden : .visible, for: .windowToolbar)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 560)
        .preferredColorScheme(workspace.appearance.colorScheme)
        .onAppear {
            controller.apply(configuration: configurationStore.configuration)
            controller.bootstrapIfNeeded()
        }
        .onChange(of: configurationStore.configuration) { _, configuration in
            controller.apply(configuration: configuration)
        }
        .onReceive(maintenanceTimer) { date in
            controller.handleDayRollover(now: date)
            controller.refreshExternalChanges()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            controller.flushSaves()
        }
        .sheet(item: $workspace.sheet) { sheet in
            WorkspaceSheetView(sheet: sheet, controller: controller, workspace: workspace)
        }
        .alert(item: Binding(get: { controller.notice }, set: { controller.notice = $0 })) { notice in
            if notice.kind == .saveError && controller.hasUnsavedChanges {
                return Alert(title: Text(notice.title), message: Text(notice.message),
                    primaryButton: .default(Text("Retry Save")) {
                        // Let the current alert dismiss before publishing a retry error.
                        DispatchQueue.main.async { _ = controller.flushAllSaves() }
                    }, secondaryButton: .cancel(Text("Keep Editing")))
            }
            return Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { workspace.sidebarVisible && !workspace.focusMode ? .all : .detailOnly },
            set: { visibility in
                if !workspace.focusMode { workspace.sidebarVisible = visibility != .detailOnly }
            }
        )
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(id: "stream", placement: .navigation) { streamBreadcrumb }
                .sharedBackgroundVisibility(.visible)
        } else {
            ToolbarItem(id: "stream", placement: .navigation) { streamBreadcrumb }
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        } else {
            ToolbarItem(placement: .primaryAction) { Spacer() }
        }
        ToolbarItem(id: "calendar", placement: .primaryAction) {
            Button {
                workspace.selectedDate = visibleDate
                workspace.showsDatePicker = true
            } label: {
                Text(WorkspaceDateLabel.title(for: visibleDate, relativeTo: controller.today))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 144)
            }
            .popover(isPresented: $workspace.showsDatePicker) {
                WorkspaceCalendar(controller: controller, workspace: workspace)
            }
            .help("Jump to date")
            .accessibilityLabel("Jump to date")
            .accessibilityValue(visibleDate.formatted(date: .complete, time: .omitted))
            .accessibilityIdentifier("workspace.calendar")
        }
        if !Calendar.current.isDate(visibleDate, inSameDayAs: controller.today) {
            ToolbarItem(id: "today", placement: .primaryAction) {
                Button("Today") { controller.jumpToToday() }
                    .help("Jump to today (⇧⌘D)")
                    .accessibilityIdentifier("workspace.today")
            }
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Search notes", systemImage: "magnifyingglass") { workspace.sheet = .search }
                .help("Search notes (⇧⌘F)")
                .accessibilityIdentifier("workspace.search")
            Button("New stream", systemImage: "plus") { workspace.sheet = .newStream(nil) }
                .help("New stream (⌘N)")
                .accessibilityIdentifier("workspace.newStream")
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Commands…") { workspace.sheet = .commands }
                Divider()
                Toggle("Show Stream Tabs", isOn: $workspace.showsTabs)
                Toggle("Markdown Source", isOn: $workspace.sourceMode)
                Toggle("Focus Mode", isOn: $workspace.focusMode)
                Picker("Appearance", selection: $workspace.appearance) {
                    ForEach(WorkspaceAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                Divider()
                Button("Reveal Stream Files") {
                    if let stream = controller.stream { NSWorkspace.shared.open(stream.rootURL) }
                }
            } label: { Label("View options", systemImage: "ellipsis") }
            .menuIndicator(.hidden)
            .help("View and stream options")
            .accessibilityIdentifier("workspace.options")
        }
    }

    private var visibleDate: Date {
        controller.currentViewState.scrollDayKey.flatMap(controller.store.date(for:))
            ?? controller.activeDate ?? controller.today
    }

    private var streamBreadcrumb: some View {
        let folder = controller.folders.first { $0.id == controller.stream?.folderID }
        let parentName = folder?.name ?? "Library"
        let streamName = controller.stream?.name ?? "Daily"
        return Menu {
            ForEach(controller.streams.filter { $0.folderID == folder?.id && (!$0.isArchived || $0.id == controller.stream?.id) }) { stream in
                Button { controller.selectStream(stream.id) } label: {
                    if stream.id == controller.stream?.id {
                        Label(stream.name, systemImage: "checkmark")
                    } else {
                        Text(stream.name)
                    }
                }
            }
            Divider()
            Button("Switch Stream…") { workspace.sheet = .switcher }
                .accessibilityIdentifier("workspace.allStreams")
        } label: {
            Text("\(Text(parentName).foregroundColor(.secondary))  ›  \(Text(streamName).fontWeight(.medium))")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 240, alignment: .leading)
        }
        .menuIndicator(.visible)
        .help("Switch stream (⌘O)")
        .accessibilityLabel("\(parentName), \(streamName)")
        .accessibilityIdentifier("workspace.streamSwitcher")
    }

    @ViewBuilder
    private var leaveFocusButton: some View {
        if #available(macOS 26, *) {
            focusButton.buttonStyle(.glass)
        } else {
            focusButton.buttonStyle(.bordered)
        }
    }

    private var focusButton: some View {
        Button("Leave focus mode", systemImage: "arrow.down.right.and.arrow.up.left") {
            workspace.focusMode = false
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        .help("Leave focus mode (⇧⌘↩)")
        .accessibilityIdentifier("workspace.leaveFocus")
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleTabIDs, id: \.self) { id in
                    if let stream = controller.streams.first(where: { $0.id == id }) {
                        HStack(spacing: 2) {
                            Toggle(stream.name, isOn: Binding(
                                get: { controller.stream?.id == id },
                                set: { selected in if selected { controller.selectStream(id) } }
                            ))
                            .toggleStyle(.button)
                            .buttonStyle(.accessoryBar)
                            .lineLimit(1)
                            if controller.openStreamIDs.contains(id) {
                                Button("Close \(stream.name) tab", systemImage: "xmark") {
                                    controller.closeStreamTab(id)
                                    if controller.openStreamIDs.isEmpty { workspace.showsTabs = false }
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .imageScale(.small)
                                .help("Close \(stream.name) tab")
                            } else {
                                Button("Keep \(stream.name) open in a tab", systemImage: "pin") {
                                    controller.openStreamTab(id)
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .imageScale(.small)
                                .help("Keep \(stream.name) open in a tab")
                            }
                        }
                        .draggable(id.uuidString)
                        .dropDestination(for: String.self) { values, _ in
                            guard let value = values.first, let dragged = UUID(uuidString: value), controller.openStreamIDs.contains(dragged), dragged != id else { return false }
                            var ids = controller.openStreamIDs.filter { $0 != dragged }
                            guard let index = ids.firstIndex(of: id) else { return false }
                            ids.insert(dragged, at: index)
                            controller.reorderOpenStreams(ids)
                            return true
                        }
                    }
                }
                Button("Open stream in tab", systemImage: "plus") { workspace.sheet = .tabSwitcher }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .imageScale(.small)
                    .help("Open stream in tab")
            }
            .controlSize(.small)
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Stream tabs")
    }

    private var visibleTabIDs: [UUID] {
        guard let selected = controller.stream?.id, !controller.openStreamIDs.contains(selected) else { return controller.openStreamIDs }
        return controller.openStreamIDs + [selected]
    }

    private var timeline: some View {
        let streamID = controller.stream?.id
        let libraryID = controller.store.libraryID
        return TimelineCollectionView(
            days: controller.days,
            today: controller.today,
            activeDayID: controller.activeDayID,
            minimizedDayIDs: controller.minimizedDayIDs,
            searchQuery: controller.searchQuery,
            configuration: configurationStore.configuration,
            sourceMode: workspace.sourceMode,
            streamLinkTargets: controller.streams.filter { !$0.isArchived }.map { stream in
                MarkdownStreamLinkTarget(id: stream.id, name: stream.name,
                    qualifiedName: controller.folders.first(where: { $0.id == stream.folderID }).map { "\($0.name)/\(stream.name)" })
            },
            onOpenStream: { targetID in
                guard controller.store.libraryID == libraryID, controller.stream?.id == streamID,
                      controller.streams.contains(where: { $0.id == targetID && !$0.isArchived }) else { return }
                controller.selectStream(targetID)
            },
            canLoadOlderDays: controller.canLoadOlderDays,
            topSpacerHeight: controller.topSpacerHeight,
            bottomSpacerHeight: controller.bottomSpacerHeight,
            scrollRequest: controller.scrollRequest,
            onFocus: { date in
                guard controller.stream?.id == streamID, controller.store.libraryID == libraryID else { return }
                controller.setActiveDate(date)
            },
            onChange: { date, text in
                if let streamID { controller.updateText(for: date, streamID: streamID, libraryID: libraryID, text: text) }
            },
            onToggleMinimized: { date in
                guard controller.stream?.id == streamID, controller.store.libraryID == libraryID else { return }
                controller.toggleDayMinimized(date)
            },
            onLoadOlder: {
                guard controller.stream?.id == streamID, controller.store.libraryID == libraryID else { return }
                controller.loadOlderWindow()
            },
            onLoadNewer: {
                guard controller.stream?.id == streamID, controller.store.libraryID == libraryID else { return }
                controller.loadNewerWindow()
            },
            viewState: controller.currentViewState,
            onViewStateChange: { state in
                guard controller.stream?.id == streamID, controller.store.libraryID == libraryID else { return }
                controller.updateViewState(state)
            },
            onSaveWorkspace: {
                guard controller.stream?.id == streamID, controller.store.libraryID == libraryID else { return }
                controller.flushSaves()
            }
        )
        .background(CurrentTheme.pageBackground)
    }
}

@MainActor
final class DaySectionModel: @preconcurrency ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private(set) var document: DayDocument
    private(set) var isToday: Bool
    private(set) var isActive: Bool
    private(set) var isMinimized: Bool
    private(set) var searchQuery: String
    private(set) var configuration: CurrentConfiguration
    private(set) var sourceMode: Bool
    private(set) var allowsEditorFocus: Bool
    private(set) var streamLinkTargets: [MarkdownStreamLinkTarget]
    var onOpenStream: (UUID) -> Void
    var onFocus: () -> Void
    var onChange: (String) -> Void
    var onToggleMinimized: () -> Void

    init(
        document: DayDocument,
        isToday: Bool,
        isActive: Bool,
        isMinimized: Bool,
        searchQuery: String,
        configuration: CurrentConfiguration,
        sourceMode: Bool = false,
        allowsEditorFocus: Bool = true,
        streamLinkTargets: [MarkdownStreamLinkTarget] = [],
        onOpenStream: @escaping (UUID) -> Void = { _ in },
        onFocus: @escaping () -> Void,
        onChange: @escaping (String) -> Void,
        onToggleMinimized: @escaping () -> Void
    ) {
        self.document = document
        self.isToday = isToday
        self.isActive = isActive
        self.isMinimized = isMinimized
        self.searchQuery = searchQuery
        self.configuration = configuration
        self.sourceMode = sourceMode
        self.allowsEditorFocus = allowsEditorFocus
        self.streamLinkTargets = streamLinkTargets
        self.onOpenStream = onOpenStream
        self.onFocus = onFocus
        self.onChange = onChange
        self.onToggleMinimized = onToggleMinimized
    }

    func update(
        document: DayDocument,
        isToday: Bool,
        isActive: Bool,
        isMinimized: Bool,
        searchQuery: String,
        configuration: CurrentConfiguration,
        sourceMode: Bool = false,
        allowsEditorFocus: Bool = true,
        streamLinkTargets: [MarkdownStreamLinkTarget] = [],
        onOpenStream: @escaping (UUID) -> Void = { _ in },
        onFocus: @escaping () -> Void,
        onChange: @escaping (String) -> Void,
        onToggleMinimized: @escaping () -> Void
    ) {
        let viewChanged = document != self.document
            || isToday != self.isToday
            || isActive != self.isActive
            || isMinimized != self.isMinimized
            || searchQuery != self.searchQuery
            || configuration != self.configuration
            || sourceMode != self.sourceMode
            || allowsEditorFocus != self.allowsEditorFocus
            || streamLinkTargets != self.streamLinkTargets

        self.onOpenStream = onOpenStream
        self.onFocus = onFocus
        self.onChange = onChange
        self.onToggleMinimized = onToggleMinimized

        guard viewChanged else { return }

        objectWillChange.send()
        self.document = document
        self.isToday = isToday
        self.isActive = isActive
        self.isMinimized = isMinimized
        self.searchQuery = searchQuery
        self.configuration = configuration
        self.sourceMode = sourceMode
        self.allowsEditorFocus = allowsEditorFocus
        self.streamLinkTargets = streamLinkTargets
    }

    func updateSaveState(_ document: DayDocument) {
        guard document.id == self.document.id,
              document.isDirty != self.document.isDirty || document.lastSavedText != self.document.lastSavedText else { return }
        objectWillChange.send()
        self.document.isDirty = document.isDirty
        self.document.lastSavedText = document.lastSavedText
    }
}

struct DaySectionView: View {
    @ObservedObject private var model: DaySectionModel

    @State private var text: String
    @State private var editorHeight: CGFloat

    init(model: DaySectionModel) {
        self.model = model
        let document = model.document
        let isToday = model.isToday
        _text = State(initialValue: document.text)
        _editorHeight = State(
            initialValue: isToday
                ? TimelineRowHeightCalculator.todayEmptyEditorMinimumHeight
                : TimelineRowHeightCalculator.expandedEditorMinimumHeight
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayDivider

            if isExpanded {
                editorSurface
                    .padding(.top, CurrentTheme.dayEditorTopPadding)
            }
        }
        .padding(.top, daySectionTopPadding)
        .padding(.bottom, daySectionBottomPadding)
        .padding(.horizontal, 0)
        .background(searchHit ? CurrentTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .transaction { transaction in
            transaction.animation = nil
        }
        .onChange(of: text) { _, newText in
            // The active row keeps its native buffer while save metadata updates.
            // An undo can return to the model's older text and must still be saved.
            model.onChange(newText)
        }
        .onChange(of: model.document.text) { _, newText in
            if newText != text {
                text = newText
            }
        }
    }

    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            MarkdownEditorView(
                text: $text,
                measuredHeight: $editorHeight,
                dayID: model.document.id,
                configuration: model.configuration,
                sourceMode: model.sourceMode,
                documentURL: model.document.fileURL,
                focusOnAppear: model.isActive && model.allowsEditorFocus,
                minimumHeight: minimumEditorHeight,
                onFocus: model.onFocus,
                streamLinkTargets: model.streamLinkTargets,
                onOpenStream: model.onOpenStream
            )
            .id(model.document.id)
            .frame(height: editorHeight)

            if model.isToday && text.isEmpty {
                Text("Start writing…")
                    .font(CurrentTheme.editorSwiftUIFont(configuration: model.configuration))
                    .foregroundStyle(CurrentTheme.mutedText)
                    .padding(.top, CurrentTheme.editorVerticalInset + 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private var dayDivider: some View {
        Button {
            handleDayDividerTap()
        } label: {
            HStack(spacing: 0) {
                if canToggleMinimized {
                    Image(systemName: model.isMinimized ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(CurrentTheme.mutedText)
                        .frame(width: 16, alignment: .leading)
                }
                Text(dayTitle)
                    .font(CurrentTheme.dayLabel)
                    .foregroundStyle(dayLabelColor)
                    .lineLimit(1)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)

                saveStateSlot
                    .padding(.leading, CurrentTheme.dayDividerDateStatusSpacing)
                    .padding(.trailing, CurrentTheme.dayDividerStatusLineSpacing)

                if model.isMinimized && hasText {
                    Text(collapsedExcerpt)
                        .font(.system(size: 12))
                        .foregroundStyle(CurrentTheme.secondaryText)
                        .lineLimit(1)
                        .accessibilityIdentifier("timeline.collapsedExcerpt")
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(dayDividerHelp)
        .accessibilityLabel("\(dayTitle)\(model.isMinimized && hasText ? ", " + collapsedExcerpt : "")")
        .accessibilityValue(canToggleMinimized ? (model.isMinimized ? "Collapsed" : "Expanded") : "")
    }

    private var saveStateSlot: some View {
        Circle()
            .fill(saveStateOrbColor)
            .frame(width: CurrentTheme.daySaveStateOrbSize, height: CurrentTheme.daySaveStateOrbSize)
            .opacity(showsSaveStateOrb ? 1 : 0)
            .help(model.document.isDirty ? "Saving" : "Saved")
            .accessibilityHidden(!showsSaveStateOrb)
    }

    private var minimumEditorHeight: CGFloat {
        if model.isToday { return TimelineRowHeightCalculator.todayEmptyEditorMinimumHeight }
        return TimelineRowHeightCalculator.expandedEditorMinimumHeight
    }

    private var hasText: Bool {
        MarkdownBlockRendering.hasRenderedContent(in: text)
    }

    private var isExpanded: Bool {
        !model.isMinimized && (model.isToday || model.isActive || hasText)
    }

    private var daySectionTopPadding: CGFloat {
        if isExpanded {
            return CurrentTheme.daySectionVerticalPaddingExpanded
        }

        return hasText ? CurrentTheme.daySectionVerticalPaddingExpanded : CurrentTheme.daySectionVerticalPaddingCollapsed
    }

    private var daySectionBottomPadding: CGFloat {
        if isExpanded {
            return CurrentTheme.daySectionVerticalPaddingExpanded
        }

        if hasText {
            return max(
                0,
                TimelineRowHeightCalculator.collapsedEmptyDayHeight
                - CurrentTheme.daySectionVerticalPaddingExpanded
                - CurrentTheme.dayDividerIntrinsicHeight
            )
        }

        return CurrentTheme.daySectionVerticalPaddingCollapsed
    }

    private var canToggleMinimized: Bool {
        !model.isToday && hasText
    }

    private var collapsedExcerpt: String {
        MarkdownSearchExcerpt.preview(source: text)
    }

    private func handleDayDividerTap() {
        if canToggleMinimized {
            model.onToggleMinimized()
        } else {
            model.onFocus()
        }
    }

    private var dayDividerHelp: String {
        if model.isToday { return "Focus today" }
        if canToggleMinimized {
            return model.isMinimized ? "Expand day" : "Minimize day"
        }
        return "Focus day"
    }

    private var dayTitle: String {
        if model.isToday {
            return "Today · \(DayFormatting.shortTitle(for: model.document.date))"
        }
        return DayFormatting.shortTitle(for: model.document.date)
    }

    private var dayLabelColor: Color {
        if model.isToday || (model.isActive && !model.isMinimized) {
            return CurrentTheme.secondaryText.opacity(0.86)
        }
        return CurrentTheme.mutedText.opacity(0.94)
    }

    private var showsSaveStateOrb: Bool {
        model.document.isDirty
    }

    private var saveStateOrbColor: Color {
        model.document.isDirty ? CurrentTheme.accent.opacity(0.58) : CurrentTheme.mutedText.opacity(0.34)
    }

    private var searchHit: Bool {
        let query = model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !query.isEmpty && text.localizedStandardContains(query)
    }
}

public struct CurrentCommands: Commands {
    @ObservedObject private var controller: TimelineController
    @ObservedObject private var configurationStore: CurrentConfigurationStore
    @ObservedObject private var workspace: WorkspaceViewState

    public init(
        controller: TimelineController,
        configurationStore: CurrentConfigurationStore,
        workspace: WorkspaceViewState = WorkspaceViewState()
    ) {
        self.controller = controller
        self.configurationStore = configurationStore
        self.workspace = workspace
    }

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Edit Settings...") {
                openConfigFile()
            }
            .keyboardShortcut(",", modifiers: [.command])

            Button("Reload Settings") {
                reloadConfig(showDiagnostics: true)
            }
            .keyboardShortcut(",", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .newItem) {
            Button("New Stream…") { workspace.sheet = .newStream(nil) }
                .keyboardShortcut("n", modifiers: [.command])
            Button("New Folder…") { workspace.sheet = .newFolder }
            Button("Switch Stream…") { workspace.sheet = .switcher }
                .keyboardShortcut("o", modifiers: [.command])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Notes") { _ = controller.flushAllSaves() }
                .keyboardShortcut("s", modifiers: [.command])
        }

        CommandGroup(after: .textEditing) {
            Button("Search All Notes…") { workspace.sheet = .search }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Commands…") { workspace.sheet = .commands }
                .keyboardShortcut("k", modifiers: [.command])
        }

        CommandGroup(after: .sidebar) {
            Toggle("Show Sidebar", isOn: Binding(
                get: { workspace.sidebarVisible && !workspace.focusMode },
                set: { visible in
                    if visible { workspace.focusMode = false }
                    workspace.sidebarVisible = visible
                }
            ))
                .keyboardShortcut("\\", modifiers: [.command])
            Toggle("Show Stream Tabs", isOn: $workspace.showsTabs)
            Toggle("Focus Mode", isOn: $workspace.focusMode)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Toggle("Markdown Source", isOn: $workspace.sourceMode)
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Picker("Appearance", selection: $workspace.appearance) {
                ForEach(WorkspaceAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }

        CommandMenu("Stream") {
            Button("Jump to Today") {
                controller.jumpToToday()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Jump to Date…") {
                workspace.focusMode = false
                workspace.selectedDate = controller.currentViewState.scrollDayKey.flatMap(controller.store.date(for:))
                    ?? controller.activeDate ?? controller.today
                workspace.showsDatePicker = true
            }

            Button("Insert Timestamp") {
                guard let editor = MarkdownTextView.activeEditor,
                      editor.currentDayID == controller.activeDayID,
                      editor.window != nil else { return }
                MarkdownTextView.insertTimestampIntoActiveEditor()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Reveal Stream Files") {
                if let stream = controller.stream {
                    NSWorkspace.shared.activateFileViewerSelecting([stream.rootURL])
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }

    private func openConfigFile() {
        do {
            let url = try configurationStore.ensureEditableConfigurationFile()
            NSWorkspace.shared.open(url)
        } catch {
            controller.notice = TimelineNotice(
                kind: .saveError,
                title: "Could not open config",
                message: error.localizedDescription
            )
        }
    }

    private func reloadConfig(showDiagnostics: Bool) {
        let diagnostics = configurationStore.reload()
        controller.apply(configuration: configurationStore.configuration)
        guard showDiagnostics, !diagnostics.isEmpty else { return }
        controller.notice = TimelineNotice(
            kind: .info,
            title: "Config reloaded with notes",
            message: diagnostics.map(\.displayMessage).prefix(5).joined(separator: "\n")
        )
    }

}
