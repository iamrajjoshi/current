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
            topBar
            hairline
            timeline
            hairline
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

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Current")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CurrentTheme.text)
                Text(controller.stream?.name ?? "Daily")
                    .font(CurrentTheme.tinyLabel)
                    .foregroundStyle(CurrentTheme.secondaryText)
            }
            .frame(width: 120, alignment: .leading)

            Spacer(minLength: 16)

            searchField

            Spacer(minLength: 16)

            Button {
                controller.jumpToToday()
            } label: {
                Image(systemName: "scope")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Jump to Today")

            Button {
                MarkdownTextView.insertTimestampIntoActiveEditor()
            } label: {
                Image(systemName: "clock")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Insert Timestamp")

            Menu {
                Button("Copy Current Day") {
                    copy(controller.copyCurrentDayMarkdown())
                }
                Button("Copy Visible Stream") {
                    copy(controller.copyVisibleStreamMarkdown())
                }
                Divider()
                Button("Reveal Stream Files") {
                    revealStreamFiles()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Stream Actions")
        }
        .foregroundStyle(CurrentTheme.secondaryText)
        .padding(.leading, 92)
        .padding(.trailing, 22)
        .frame(height: 52)
        .background(.ultraThinMaterial)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Find loaded days", text: $controller.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 210)
                .onSubmit {
                    controller.scrollToFirstSearchMatch()
                }

            let count = controller.searchMatchCount()
            if !controller.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
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
                                onChange: { text in
                                    controller.updateText(for: document.date, text: text)
                                }
                            )
                            .id(document.id)
                        }

                        LoadOlderView {
                            controller.loadOlderDays()
                        }
                    }
                    .frame(maxWidth: CurrentTheme.contentMaxWidth, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 56)
                .padding(.top, 28)
                .padding(.bottom, 30)
            }
            .background(CurrentTheme.pageBackground)
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
        HStack {
            Text("Daily")
                .font(CurrentTheme.tinyLabel)
                .foregroundStyle(CurrentTheme.secondaryText)

            Spacer()

            Text(todayStats)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Spacer()

            Button {
                copy(controller.copyCurrentDayMarkdown())
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Copy Current Day")

            Button {
                revealStreamFiles()
            } label: {
                Image(systemName: "folder")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Reveal Stream Files")
        }
        .foregroundStyle(CurrentTheme.secondaryText)
        .padding(.horizontal, 22)
        .frame(height: 40)
        .background(.ultraThinMaterial)
    }

    private var todayStats: String {
        let text = controller.copyCurrentDayMarkdown()
        let words = text.split { $0.isWhitespace }.count
        let characters = text.count
        return "\(words) words · \(characters) characters"
    }

    private var displayedDays: [DayDocument] {
        controller.days
    }

    private var hairline: some View {
        Rectangle()
            .fill(CurrentTheme.divider)
            .frame(height: 1)
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

struct LoadOlderView: View {
    var load: () -> Void

    var body: some View {
        Button {
            load()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.down")
                Text("Earlier days")
            }
            .font(CurrentTheme.tinyLabel)
            .foregroundStyle(.tertiary)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 18)
    }
}

struct DaySectionView: View {
    var document: DayDocument
    var isToday: Bool
    var searchQuery: String
    var onChange: (String) -> Void

    @State private var text: String
    @State private var editorHeight: CGFloat
    @State private var isExpanded: Bool

    init(
        document: DayDocument,
        isToday: Bool,
        searchQuery: String,
        onChange: @escaping (String) -> Void
    ) {
        self.document = document
        self.isToday = isToday
        self.searchQuery = searchQuery
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
                    .padding(.top, 18)
            }
        }
        .padding(.vertical, isExpanded ? 16 : 8)
        .padding(.horizontal, 2)
        .background(searchHit ? CurrentTheme.accent.opacity(0.055) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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
                minimumHeight: minimumEditorHeight
            )
            .frame(height: editorHeight)

            if isToday && text.isEmpty {
                Text("Start writing...")
                    .font(.system(size: CurrentTheme.editorFontSize, design: .monospaced))
                    .foregroundStyle(.tertiary)
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
                    .foregroundStyle(isToday ? CurrentTheme.text.opacity(0.72) : CurrentTheme.secondaryText)
                    .lineLimit(1)

                if document.isDirty {
                    Circle()
                        .fill(CurrentTheme.mutedAccent)
                        .frame(width: 5, height: 5)
                }

                Rectangle()
                    .fill(CurrentTheme.divider)
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
            return "Today - \(DayFormatting.visibleTitle(for: document.date))"
        }
        return DayFormatting.visibleTitle(for: document.date)
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
