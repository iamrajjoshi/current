import AppKit
import SwiftUI

public struct ContentView: View {
    @ObservedObject private var controller: TimelineController
    private let maintenanceTimer = Timer.publish(every: 45, on: .main, in: .common).autoconnect()

    public init(controller: TimelineController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            timeline
            bottomBar
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
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: 0)

                    LazyVStack(spacing: 0) {
                        ForEach(displayedDays) { document in
                            DaySectionView(
                                document: document,
                                isToday: Calendar.current.isDate(document.date, inSameDayAs: controller.today),
                                searchQuery: controller.searchQuery,
                                onFocus: {
                                    controller.setActiveDate(document.date)
                                },
                                onChange: { text in
                                    controller.updateText(for: document.date, text: text)
                                }
                            )
                            .id(document.id)
                        }

                        if controller.canLoadOlderDays {
                            HistoryLoaderView(oldestDayID: displayedDays.last?.id) {
                                controller.loadOlderDays()
                            }
                        }
                    }
                    .frame(maxWidth: CurrentTheme.contentMaxWidth, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 56)
                .padding(.top, 44)
                .padding(.bottom, 26)
            }
            .background(CurrentTheme.pageBackground)
            .coordinateSpace(name: "timelineScroll")
            .onChange(of: controller.scrollTargetID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
            .onChange(of: controller.searchQuery) { _, _ in
                if let id = controller.firstSearchMatchID() {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        ZStack {
            Text(activeStats)
                .font(CurrentTheme.metadata)
                .foregroundStyle(CurrentTheme.mutedText)
                .monospacedDigit()

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
        let text = controller.activeDocument?.text ?? ""
        let words = text.split { $0.isWhitespace }.count
        let characters = text.count
        return "\(words) words · \(characters) characters"
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
        configuration.label
            .foregroundStyle(configuration.isPressed ? CurrentTheme.primaryText : CurrentTheme.secondaryText)
            .background(
                configuration.isPressed ? CurrentTheme.fieldBackgroundActive : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
    }
}

struct HistoryLoaderView: View {
    var oldestDayID: String?
    var load: () -> Void
    @State private var lastRequestedOldestDayID: String?
    @State private var currentOldestDayID: String?
    @State private var currentMinY: CGFloat = .infinity
    @State private var isArmed = true
    @State private var autoFillTask: Task<Void, Never>?

    private let triggerY: CGFloat = 760
    private let resetY: CGFloat = 920

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: HistoryLoaderOffsetKey.self,
                    value: proxy.frame(in: .named("timelineScroll")).minY
                )
        }
        .frame(height: 120)
        .onAppear {
            currentOldestDayID = oldestDayID
        }
        .onDisappear {
            autoFillTask?.cancel()
            autoFillTask = nil
        }
        .onChange(of: oldestDayID) { _, newValue in
            currentOldestDayID = newValue
            if currentMinY < triggerY {
                isArmed = true
                loadIfNeeded()
            }
        }
        .onPreferenceChange(HistoryLoaderOffsetKey.self) { minY in
            currentMinY = minY

            if minY > resetY {
                isArmed = true
                autoFillTask?.cancel()
                autoFillTask = nil
            }

            if minY < triggerY {
                loadIfNeeded()
            }
        }
    }

    private func loadIfNeeded() {
        let targetOldestDayID = currentOldestDayID ?? oldestDayID
        guard isArmed, let targetOldestDayID, targetOldestDayID != lastRequestedOldestDayID else { return }
        isArmed = false
        lastRequestedOldestDayID = targetOldestDayID
        Task { @MainActor in
            load()
        }
        scheduleAutoFillIfStillNearBottom()
    }

    private func scheduleAutoFillIfStillNearBottom() {
        autoFillTask?.cancel()
        autoFillTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            if currentMinY < triggerY {
                isArmed = true
                loadIfNeeded()
            }
        }
    }
}

private struct HistoryLoaderOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DaySectionView: View {
    var document: DayDocument
    var isToday: Bool
    var searchQuery: String
    var onFocus: () -> Void
    var onChange: (String) -> Void

    @State private var text: String
    @State private var editorHeight: CGFloat
    @State private var isExpanded: Bool

    init(
        document: DayDocument,
        isToday: Bool,
        searchQuery: String,
        onFocus: @escaping () -> Void,
        onChange: @escaping (String) -> Void
    ) {
        self.document = document
        self.isToday = isToday
        self.searchQuery = searchQuery
        self.onFocus = onFocus
        self.onChange = onChange
        let hasText = !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        _text = State(initialValue: document.text)
        _editorHeight = State(initialValue: isToday && !hasText ? 280 : 74)
        _isExpanded = State(initialValue: isToday || hasText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayDivider

            if isExpanded {
                editorSurface
                    .padding(.top, 14)
            }
        }
        .padding(.vertical, isExpanded ? 13 : 6)
        .padding(.horizontal, 0)
        .background(searchHit ? CurrentTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: text) { _, newText in
            if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isExpanded = true
            }
            onChange(newText)
        }
        .onChange(of: document.text) { _, newText in
            if newText != text {
                text = newText
                if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    isExpanded = true
                }
            }
        }
    }

    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            MarkdownEditorView(
                text: $text,
                measuredHeight: $editorHeight,
                focusOnAppear: isToday,
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
            if !isToday || !text.isEmpty {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(dayTitle)
                    .font(CurrentTheme.dayLabel)
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(isToday ? CurrentTheme.secondaryText : CurrentTheme.mutedText)
                    .lineLimit(1)

                Rectangle()
                    .fill(CurrentTheme.softDivider)
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

    private var dayTitle: String {
        if isToday {
            return "Today · \(DayFormatting.shortTitle(for: document.date))"
        }
        return DayFormatting.shortTitle(for: document.date)
    }

    private var searchHit: Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !query.isEmpty && text.localizedStandardContains(query)
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
