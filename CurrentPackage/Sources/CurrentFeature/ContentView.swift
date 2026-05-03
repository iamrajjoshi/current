import AppKit
import Combine
import SwiftUI

public struct ContentView: View {
    @ObservedObject private var controller: TimelineController
    @ObservedObject private var configurationStore: CurrentConfigurationStore
    private let maintenanceTimer = Timer.publish(every: 45, on: .main, in: .common).autoconnect()

    public init(
        controller: TimelineController,
        configurationStore: CurrentConfigurationStore = CurrentConfigurationStore()
    ) {
        self.controller = controller
        self.configurationStore = configurationStore
    }

    public var body: some View {
        ZStack(alignment: .top) {
            timeline

            timelineTopFade
        }
        .frame(minWidth: 820, minHeight: 640)
        .background(CurrentTheme.pageBackground)
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
        .onChange(of: controller.searchQuery) { _, _ in
            controller.scrollToFirstSearchMatch()
        }
        .alert(item: Binding(
            get: { controller.notice },
            set: { controller.notice = $0 }
        )) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var timeline: some View {
        TimelineCollectionView(
            days: displayedDays,
            today: controller.today,
            activeDayID: controller.activeDayID,
            minimizedDayIDs: controller.minimizedDayIDs,
            searchQuery: controller.searchQuery,
            configuration: configurationStore.configuration,
            canLoadOlderDays: controller.canLoadOlderDays,
            topSpacerHeight: controller.topSpacerHeight,
            bottomSpacerHeight: controller.bottomSpacerHeight,
            scrollRequest: controller.scrollRequest,
            onFocus: { date in
                controller.setActiveDate(date)
            },
            onChange: { date, text in
                controller.updateText(for: date, text: text)
            },
            onToggleMinimized: { date in
                controller.toggleDayMinimized(date)
            },
            onLoadOlder: {
                controller.loadOlderWindow()
            },
            onLoadNewer: {
                controller.loadNewerWindow()
            }
        )
        .background(CurrentTheme.pageBackground)
    }

    private var timelineTopFade: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                CurrentTheme.pageBackground
                    .frame(height: CurrentTheme.timelineTopFadeSolidHeight)

                LinearGradient(
                    colors: [
                        CurrentTheme.pageBackground,
                        CurrentTheme.pageBackground.opacity(0.98),
                        CurrentTheme.pageBackground.opacity(0.82),
                        CurrentTheme.pageBackground.opacity(0.38),
                        CurrentTheme.pageBackground.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: CurrentTheme.timelineTopFadeHeight)
            .frame(maxWidth: .infinity)

            Color.clear
                .frame(width: CurrentTheme.timelineScrollbarFadeClearance)
        }
        .frame(height: CurrentTheme.timelineTopFadeHeight)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private var displayedDays: [DayDocument] {
        controller.days
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
        let hasText = !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        _text = State(initialValue: document.text)
        _editorHeight = State(
            initialValue: isToday && !hasText
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
            guard newText != model.document.text else { return }
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
                focusOnAppear: model.isToday,
                minimumHeight: minimumEditorHeight,
                onFocus: model.onFocus
            )
            .frame(height: editorHeight)

            if model.isToday && text.isEmpty {
                Text("Start writing...")
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
                Text(dayTitle)
                    .font(CurrentTheme.dayLabel)
                    .tracking(0.72)
                    .textCase(.uppercase)
                    .foregroundStyle(dayLabelColor)
                    .lineLimit(1)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)

                saveStateSlot
                    .padding(.leading, CurrentTheme.dayDividerDateStatusSpacing)
                    .padding(.trailing, CurrentTheme.dayDividerStatusLineSpacing)

                Rectangle()
                    .fill(dayDividerColor)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(dayDividerHelp)
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
        if model.isToday && text.isEmpty { return 280 }
        return 64
    }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isExpanded: Bool {
        !model.isMinimized && (model.isToday || model.isActive || hasText)
    }

    private var daySectionTopPadding: CGFloat {
        hasText ? CurrentTheme.daySectionVerticalPaddingExpanded : CurrentTheme.daySectionVerticalPaddingCollapsed
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

    private var dayDividerColor: Color {
        if model.isToday || (model.isActive && !model.isMinimized) {
            return CurrentTheme.dayDivider.opacity(1)
        }
        return CurrentTheme.dayDivider.opacity(0.78)
    }

    private var showsSaveStateOrb: Bool {
        (model.isActive && !model.isMinimized) || model.document.isDirty
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

    public init(
        controller: TimelineController,
        configurationStore: CurrentConfigurationStore
    ) {
        self.controller = controller
        self.configurationStore = configurationStore
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

        CommandMenu("Stream") {
            Button("Jump to Today") {
                controller.jumpToToday()
            }
            .keyboardShortcut("j", modifiers: [.command])

            Button("Insert Timestamp") {
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
