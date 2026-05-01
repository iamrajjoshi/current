import AppKit
import SwiftUI

public struct ContentView: View {
    @ObservedObject private var controller: TimelineController
    private let maintenanceTimer = Timer.publish(every: 45, on: .main, in: .common).autoconnect()

    public init(controller: TimelineController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                timeline
                bottomBar
            }

            timelineTopFade
        }
        .frame(minWidth: 820, minHeight: 640)
        .background(CurrentTheme.pageBackground)
        .onAppear {
            controller.bootstrapIfNeeded()
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
            searchQuery: controller.searchQuery,
            topSpacerHeight: controller.topSpacerHeight,
            bottomSpacerHeight: controller.bottomSpacerHeight,
            scrollRequest: controller.scrollRequest,
            onFocus: { date in
                controller.setActiveDate(date)
            },
            onChange: { date, text in
                controller.updateText(for: date, text: text)
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

    private var bottomBar: some View {
        ZStack {
            HStack(spacing: 7) {
                Text(activeStats)
                    .font(CurrentTheme.metadata)
                    .foregroundStyle(CurrentTheme.mutedText)
                    .monospacedDigit()

                Circle()
                    .fill(activeDocumentIsDirty ? CurrentTheme.accent.opacity(0.58) : CurrentTheme.mutedText.opacity(0.34))
                    .frame(width: 5, height: 5)
                    .help(activeDocumentIsDirty ? "Saving" : "Saved")
            }

            HStack {
                Spacer()

                Button {
                    copy(controller.activeDocument?.text ?? "")
                } label: {
                    chromeIcon("doc.on.doc")
                }
                .buttonStyle(QuietChromeButtonStyle())
                .help("Copy Active Day")

                Button {
                    revealStreamFiles()
                } label: {
                    chromeIcon("folder")
                }
                .buttonStyle(QuietChromeButtonStyle())
                .help("Reveal Stream Files")
            }
            .padding(.leading, 20)
            .padding(.trailing, 18)
        }
        .foregroundStyle(CurrentTheme.secondaryText)
        .frame(height: 34)
        .background(CurrentTheme.chromeBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CurrentTheme.softDivider)
                .frame(height: 1)
        }
    }

    private var activeStats: String {
        let document = controller.activeDocument
        let text = document?.text ?? ""
        let words = text.split { $0.isWhitespace }.count
        let characters = text.count
        return "\(activeDayTitle(for: document)) · \(words) words · \(characters) characters"
    }

    private var activeDocumentIsDirty: Bool {
        controller.activeDocument?.isDirty == true
    }

    private func activeDayTitle(for document: DayDocument?) -> String {
        guard let document else { return "Today" }
        if Calendar.current.isDate(document.date, inSameDayAs: controller.today) {
            return "Today"
        }
        return DayFormatting.shortTitle(for: document.date)
    }

    private var displayedDays: [DayDocument] {
        controller.days
    }

    private func chromeIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(CurrentTheme.iconButton)
            .symbolRenderingMode(.hierarchical)
            .frame(width: 24, height: 24)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private func revealStreamFiles() {
        guard let stream = controller.stream else { return }
        NSWorkspace.shared.activateFileViewerSelecting([stream.rootURL])
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

}

private struct QuietChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietChromeButton(configuration: configuration)
    }

    private struct QuietChromeButton: View {
        let configuration: ButtonStyle.Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(configuration.isPressed ? CurrentTheme.primaryText : CurrentTheme.secondaryText)
                .background(background, in: RoundedRectangle(cornerRadius: 6))
                .onHover { isHovered = $0 }
        }

        private var background: Color {
            if configuration.isPressed {
                return CurrentTheme.fieldBackgroundActive
            }
            if isHovered {
                return CurrentTheme.fieldBackground
            }
            return .clear
        }
    }
}

struct DaySectionView: View {
    var document: DayDocument
    var isToday: Bool
    var isActive: Bool
    var searchQuery: String
    var onFocus: () -> Void
    var onChange: (String) -> Void

    @State private var text: String
    @State private var editorHeight: CGFloat

    init(
        document: DayDocument,
        isToday: Bool,
        isActive: Bool,
        searchQuery: String,
        onFocus: @escaping () -> Void,
        onChange: @escaping (String) -> Void
    ) {
        self.document = document
        self.isToday = isToday
        self.isActive = isActive
        self.searchQuery = searchQuery
        self.onFocus = onFocus
        self.onChange = onChange
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
        .padding(
            .vertical,
            isExpanded ? CurrentTheme.daySectionVerticalPaddingExpanded : CurrentTheme.daySectionVerticalPaddingCollapsed
        )
        .padding(.horizontal, 0)
        .background(searchHit ? CurrentTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: text) { _, newText in
            guard newText != document.text else { return }
            onChange(newText)
        }
        .onChange(of: document.text) { _, newText in
            if newText != text {
                text = newText
            }
        }
        .onChange(of: document.id) { _, _ in
            syncDocumentState()
        }
        .onChange(of: isActive) { _, _ in
            syncDocumentState()
        }
    }

    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            MarkdownEditorView(
                text: $text,
                measuredHeight: $editorHeight,
                focusOnAppear: isToday || isActive,
                minimumHeight: minimumEditorHeight,
                onFocus: onFocus
            )
            .frame(height: editorHeight)

            if isToday && text.isEmpty {
                Text("Start writing...")
                    .font(.system(size: CurrentTheme.editorFontSize, design: .monospaced))
                    .foregroundStyle(CurrentTheme.mutedText)
                    .padding(.top, CurrentTheme.editorVerticalInset + 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private var dayDivider: some View {
        Button {
            onFocus()
        } label: {
            HStack(spacing: CurrentTheme.dayDividerSpacing) {
                Text(dayTitle)
                    .font(CurrentTheme.dayLabel)
                    .tracking(0.72)
                    .textCase(.uppercase)
                    .foregroundStyle(dayLabelColor)
                    .lineLimit(1)
                    .monospacedDigit()
                    .frame(width: CurrentTheme.dayLabelRailWidth, alignment: .leading)

                Rectangle()
                    .fill(dayDividerColor)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var minimumEditorHeight: CGFloat {
        if isToday && text.isEmpty { return 280 }
        return 64
    }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isExpanded: Bool {
        isToday || isActive || hasText
    }

    private var dayTitle: String {
        if isToday {
            return "Today · \(DayFormatting.shortTitle(for: document.date))"
        }
        return DayFormatting.shortTitle(for: document.date)
    }

    private var dayLabelColor: Color {
        if isToday || isActive {
            return CurrentTheme.secondaryText.opacity(0.86)
        }
        return CurrentTheme.mutedText.opacity(0.94)
    }

    private var dayDividerColor: Color {
        if isToday || isActive {
            return CurrentTheme.dayDivider.opacity(1)
        }
        return CurrentTheme.dayDivider.opacity(0.78)
    }

    private var searchHit: Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !query.isEmpty && text.localizedStandardContains(query)
    }

    private func syncDocumentState() {
        let hasText = !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        text = document.text
        editorHeight = isToday && !hasText
            ? TimelineRowHeightCalculator.todayEmptyEditorMinimumHeight
            : TimelineRowHeightCalculator.expandedEditorMinimumHeight
    }
}

public struct CurrentCommands: Commands {
    @ObservedObject private var controller: TimelineController

    public init(controller: TimelineController) {
        self.controller = controller
    }

    public var body: some Commands {
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

            Button("Copy Current Day") {
                copy(controller.copyCurrentDayMarkdown())
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button("Copy Visible Stream") {
                copy(controller.copyVisibleStreamMarkdown())
            }

            Button("Reveal Stream Files") {
                if let stream = controller.stream {
                    NSWorkspace.shared.activateFileViewerSelecting([stream.rootURL])
                }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
