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
            header
            Divider()
            timeline
        }
        .frame(minWidth: 760, minHeight: 620)
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

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current")
                    .font(.system(size: 20, weight: .semibold))
                Text(controller.stream?.name ?? "Daily")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            searchField

            Button {
                controller.jumpToToday()
            } label: {
                Label("Jump to Today", systemImage: "scope")
            }
            .help("Jump to Today")

            Button {
                MarkdownTextView.insertTimestampIntoActiveEditor()
            } label: {
                Label("Insert Timestamp", systemImage: "clock")
            }
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
                Label("Stream Actions", systemImage: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .help("Stream Actions")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(CurrentTheme.subtleBackground.opacity(0.4))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find loaded days", text: $controller.searchQuery)
                .textFieldStyle(.plain)
                .frame(width: 190)
                .onSubmit {
                    controller.scrollToFirstSearchMatch()
                }

            let count = controller.searchMatchCount()
            if !controller.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    LoadOlderView {
                        controller.loadOlderDays()
                    }
                    .padding(.top, 12)

                    ForEach(controller.days) { document in
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
                }
                .padding(.bottom, 36)
            }
            .onChange(of: controller.scrollTargetID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .bottom)
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
    @State private var didAutoLoad = false

    var body: some View {
        Button {
            load()
        } label: {
            Label("Load Earlier Days", systemImage: "arrow.up.to.line")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
        .onAppear {
            guard !didAutoLoad else { return }
            didAutoLoad = true
            load()
        }
    }
}

struct DaySectionView: View {
    var document: DayDocument
    var isToday: Bool
    var searchQuery: String
    var onChange: (String) -> Void

    @State private var text: String
    @State private var editorHeight: CGFloat = 140

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
        _text = State(initialValue: document.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            dayDivider
            MarkdownEditorView(
                text: $text,
                measuredHeight: $editorHeight,
                focusOnAppear: isToday
            )
            .frame(minHeight: 112)
            .frame(height: editorHeight)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 12)
        .background(searchHit ? CurrentTheme.accent.opacity(0.05) : Color.clear)
        .onChange(of: text) { _, newText in
            onChange(newText)
        }
        .onChange(of: document.text) { _, newText in
            if newText != text {
                text = newText
            }
        }
    }

    private var dayDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(CurrentTheme.divider)
                .frame(height: 1)

            HStack(spacing: 8) {
                Text(isToday ? "Today" : DayFormatting.visibleTitle(for: document.date))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isToday ? CurrentTheme.accent : CurrentTheme.secondaryText)
                    .lineLimit(1)

                if document.isDirty {
                    Text("Saving")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            Rectangle()
                .fill(CurrentTheme.divider)
                .frame(height: 1)
        }
        .padding(.horizontal, 24)
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
