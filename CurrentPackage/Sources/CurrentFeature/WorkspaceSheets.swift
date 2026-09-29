import AppKit
import SwiftUI

struct WorkspaceSheetView: View {
    let sheet: WorkspaceSheet
    @ObservedObject var controller: TimelineController
    @ObservedObject var workspace: WorkspaceViewState

    var body: some View {
        switch sheet {
        case .search, .commands, .switcher, .tabSwitcher:
            WorkspacePalette(mode: sheet, controller: controller, workspace: workspace)
        case .newStream(let folder):
            WorkspaceNameSheet(title: "New stream", value: "", actionTitle: "Create stream") { name in
                if let stream = controller.createStream(name: name, folderID: folder) {
                    controller.selectStream(stream.id)
                    workspace.sheet = nil
                }
            }
        case .renameStream(let stream):
            WorkspaceNameSheet(title: "Rename stream", value: stream.name, actionTitle: "Save name") { name in
                if controller.renameStream(stream.id, name: name) { workspace.sheet = nil }
            }
        case .newFolder:
            WorkspaceNameSheet(title: "New folder", value: "", actionTitle: "Create folder") { name in
                if controller.createFolder(name: name) != nil { workspace.sheet = nil }
            }
        case .renameFolder(let folder):
            WorkspaceNameSheet(title: "Rename folder", value: folder.name, actionTitle: "Save name") { name in
                if controller.renameFolder(folder.id, name: name) { workspace.sheet = nil }
            }
        case .conflict(let conflict):
            WorkspaceConflictView(conflict: conflict, controller: controller)
        }
    }
}

private struct WorkspaceConflictView: View {
    let conflict: DocumentConflict
    @ObservedObject var controller: TimelineController
    @Environment(\.dismiss) private var dismiss
    private var currentConflict: DocumentConflict {
        controller.conflicts.first(where: { $0.id == conflict.id }) ?? conflict
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review changed note").font(.title2.weight(.semibold))
            Text("Keep both saves your edits in a separate Markdown file. Use disk replaces this editor with the external version.")
                .foregroundStyle(CurrentTheme.secondaryText)
            HStack(alignment: .top, spacing: 16) {
                version("Your edits", text: currentConflict.document.text)
                version("On disk", text: currentConflict.diskText)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use disk version") { controller.reloadConflictFromDisk(conflict.id); dismiss() }
                Button("Keep both versions") { controller.keepBothConflictVersions(conflict.id); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 720)
    }

    private func version(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView {
                Text(text).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .frame(height: 300)
            .background(CurrentTheme.appSurface, in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WorkspaceNameSheet: View {
    let title: String
    @State var value: String
    let actionTitle: String
    let action: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.weight(.semibold))
            TextField("Name", text: $value).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit(submit)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(actionTitle, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 350)
        .onAppear { focused = true }
    }

    private func submit() {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        action(name)
    }
}

private struct WorkspacePalette: View {
    let mode: WorkspaceSheet
    @ObservedObject var controller: TimelineController
    @ObservedObject var workspace: WorkspaceViewState
    @State private var query = ""
    @State private var currentStreamOnly = false
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isSearch: Bool { if case .search = mode { true } else { false } }
    private var isCommands: Bool { if case .commands = mode { true } else { false } }
    private var opensTab: Bool { if case .tabSwitcher = mode { true } else { false } }
    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreateStream: Bool { !isSearch && !isCommands && streams.isEmpty && !normalizedQuery.isEmpty }
    private var creationFolder: StreamFolder? { controller.folders.first { $0.id == controller.stream?.folderID } }
    private var title: String { isSearch ? "Search notes" : isCommands ? "Run a command" : opensTab ? "Open stream in tab" : "Switch stream" }

    private var streams: [Stream] {
        let term = normalizedQuery
        return controller.streams.filter { !$0.isArchived && (term.isEmpty || $0.name.localizedStandardContains(term) || folderName(for: $0).localizedStandardContains(term)) }
    }

    private var commands: [(String, String, @MainActor @Sendable () -> Void)] {
        let targetDayID = controller.activeDayID
        let all: [(String, String, @MainActor @Sendable () -> Void)] = [
            ("Jump to today", "calendar", { controller.jumpToToday() }),
            ("Jump to date", "calendar.badge.clock", {
                workspace.focusMode = false
                workspace.selectedDate = controller.currentViewState.scrollDayKey.flatMap(controller.store.date(for:))
                    ?? controller.activeDate ?? controller.today
                workspace.showsDatePicker = true
            }),
            ("New stream", "plus", { workspace.sheet = .newStream(nil) }),
            ("New folder", "folder.badge.plus", { workspace.sheet = .newFolder }),
            (workspace.focusMode ? "Leave focus mode" : "Enter focus mode", "arrow.up.left.and.arrow.down.right", { workspace.focusMode.toggle() }),
            (workspace.sourceMode ? "Show rendered Markdown" : "Show Markdown source", "chevron.left.forwardslash.chevron.right", { workspace.sourceMode.toggle() }),
            (workspace.showsTabs ? "Hide stream tabs" : "Show stream tabs", "rectangle.topthird.inset.filled", { workspace.showsTabs.toggle() }),
            ("Insert timestamp", "clock", {
                guard let targetDayID, controller.activeDayID == targetDayID,
                      let editor = MarkdownTextView.activeEditor,
                      editor.currentDayID == targetDayID, editor.window != nil else { return }
                MarkdownTextView.insertTimestampIntoActiveEditor()
            }),
            ("Reveal stream files", "folder", { if let stream = controller.stream { NSWorkspace.shared.open(stream.rootURL) } })
        ]
        let term = normalizedQuery
        return all.filter { term.isEmpty || $0.0.localizedStandardContains(term) }
    }

    private var resultCount: Int { isSearch ? controller.searchResults.count : isCommands ? commands.count : canCreateStream ? 1 : streams.count }

    private var resultsHeight: CGFloat {
        guard !isSearch else { return 320 }
        // Single-line rows use a 16pt text line, 24pt padding, and 3pt gaps.
        // Keep extra room for the creation hint without measuring the scroll view.
        let rows = CGFloat(resultCount) * 40 + CGFloat(max(0, resultCount - 1)) * 3
        return min(320, max(64, rows + 16 + (canCreateStream ? 28 : 0)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: isSearch ? "magnifyingglass" : isCommands ? "command" : "book.closed")
                    .foregroundStyle(CurrentTheme.secondaryText)
                TextField(title, text: $query)
                    .font(.system(size: 16)).textFieldStyle(.plain).focused($focused)
                    .onSubmit { activate(selectedIndex) }
                    .onKeyPress(.downArrow) { selectedIndex = min(max(0, resultCount - 1), selectedIndex + 1); return .handled }
                    .onKeyPress(.upArrow) { selectedIndex = max(0, selectedIndex - 1); return .handled }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain).foregroundStyle(CurrentTheme.secondaryText)
            }
            .padding(20)
            if isSearch {
                HStack {
                    Picker("Search in", selection: $currentStreamOnly) {
                        Text("All streams").tag(false)
                        Text(controller.stream?.name ?? "Current stream").tag(true)
                    }
                    .pickerStyle(.segmented).frame(width: 280)
                    Spacer()
                    if controller.isSearching { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 20).padding(.bottom, 14)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if isSearch {
                            ForEach(Array(controller.searchResults.enumerated()), id: \.element.id) { index, result in
                                paletteRow(index: index) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(result.streamName).fontWeight(.medium)
                                            Spacer()
                                            Text(DayFormatting.shortTitle(for: result.date)).foregroundStyle(CurrentTheme.secondaryText)
                                        }
                                        Text(highlightedExcerpt(result)).lineLimit(2)
                                    }
                                }
                            }
                        } else if isCommands {
                            ForEach(Array(commands.enumerated()), id: \.offset) { index, command in
                                paletteRow(index: index) { Label(command.0, systemImage: command.1) }
                            }
                        } else {
                            ForEach(Array(streams.enumerated()), id: \.element.id) { index, stream in
                                paletteRow(index: index) {
                                    HStack {
                                        Label(stream.name, systemImage: stream.slug == "daily" ? "calendar" : "book.closed")
                                        Text(folderName(for: stream)).foregroundStyle(CurrentTheme.secondaryText)
                                        Spacer()
                                        if controller.stream?.id == stream.id { Image(systemName: "checkmark").foregroundStyle(CurrentTheme.secondaryText) }
                                    }
                                }
                            }
                            if canCreateStream {
                                paletteRow(index: 0) {
                                    Label("Create “\(normalizedQuery)”", systemImage: "plus")
                                }
                                Text("Create in \(creationFolder?.name ?? "Library") · Return")
                                    .font(.system(size: 12))
                                    .foregroundStyle(CurrentTheme.secondaryText)
                                    .padding(.horizontal, 12).padding(.top, 6)
                            }
                        }
                        if resultCount == 0 && !controller.isSearching {
                            Text(normalizedQuery.isEmpty && isSearch ? "Type to search" : "No matches")
                                .foregroundStyle(CurrentTheme.secondaryText)
                                .padding(16)
                        }
                    }
                    .padding(8)
                }
                .frame(height: resultsHeight)
                .onChange(of: selectedIndex) { _, index in proxy.scrollTo(rowID(for: index)) }
                .onChange(of: query) { _, _ in proxy.scrollTo(rowID(for: 0)) }
            }
        }
        .font(.system(size: 13))
        .frame(width: 560)
        .background(CurrentTheme.pageBackground)
        .onAppear {
            focused = true
            if isSearch { controller.searchHistory("", inCurrentStream: false) }
        }
        .onChange(of: query) { _, _ in updateSearch() }
        .onChange(of: currentStreamOnly) { _, _ in updateSearch() }
    }

    private func paletteRow<Content: View>(index: Int, @ViewBuilder content: () -> Content) -> some View {
        Button { activate(index) } label: {
            content().frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(index == selectedIndex ? CurrentTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(WorkspaceControlStyle())
        .id(rowID(for: index))
    }

    private func rowID(for index: Int) -> String {
        if isSearch, controller.searchResults.indices.contains(index) { return "search-\(controller.searchResults[index].id)" }
        if isCommands, commands.indices.contains(index) { return "command-\(commands[index].0)" }
        if canCreateStream { return "create-stream" }
        if streams.indices.contains(index) { return "stream-\(streams[index].id)" }
        return "empty"
    }

    private func updateSearch() {
        selectedIndex = 0
        if isSearch { controller.searchHistory(normalizedQuery, inCurrentStream: currentStreamOnly) }
    }

    private func activate(_ index: Int) {
        guard index >= 0 && index < resultCount else { return }
        if isSearch {
            guard !controller.isSearching else { return }
            controller.openSearchResult(controller.searchResults[index])
            dismiss()
        } else if isCommands {
            let action = commands[index].2
            workspace.sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: action)
        } else {
            if canCreateStream {
                guard let stream = controller.createStream(name: normalizedQuery, folderID: creationFolder?.id) else { return }
                controller.selectStream(stream.id, openInTab: opensTab)
            } else {
                controller.selectStream(streams[index].id, openInTab: opensTab)
            }
            dismiss()
        }
    }

    private func folderName(for stream: Stream) -> String {
        controller.folders.first(where: { $0.id == stream.folderID })?.name ?? ""
    }

    private func highlightedExcerpt(_ result: LibrarySearchResult) -> AttributedString {
        var excerpt = AttributedString(result.excerpt)
        excerpt.foregroundColor = CurrentTheme.secondaryText
        if let sourceRange = Range(result.excerptMatchRange, in: result.excerpt),
           let range = Range(sourceRange, in: excerpt) {
            excerpt[range].foregroundColor = CurrentTheme.primaryText
            excerpt[range].backgroundColor = CurrentTheme.accent.opacity(0.18)
            excerpt[range].font = .system(size: 13, weight: .semibold)
        }
        return excerpt
    }
}
