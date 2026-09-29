import AppKit
import SwiftUI

struct WorkspaceSidebar: View {
    private enum Selection: Hashable { case stream(UUID) }

    @ObservedObject var controller: TimelineController
    @ObservedObject var workspace: WorkspaceViewState
    @State private var showsArchive = false

    private var visibleStreams: [Stream] { controller.streams.filter { !$0.isArchived } }
    private var archivedStreams: [Stream] { controller.streams.filter(\.isArchived) }

    private var selection: Binding<Selection?> {
        let libraryID = controller.store.libraryID
        return Binding(
            get: { controller.stream.map { .stream($0.id) } },
            set: { value in
                guard controller.store.libraryID == libraryID,
                      case .stream(let id) = value,
                      controller.streams.contains(where: { $0.id == id }) else { return }
                controller.selectStream(id, focusEditor: false)
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            if visibleStreams.contains(where: \.isPinned) {
                Section("Pinned") {
                    ForEach(visibleStreams.filter(\.isPinned)) { stream in streamRow(stream) }
                }
            }
            Section {
                ForEach(visibleStreams.filter { $0.folderID == nil && !$0.isPinned }) { stream in streamRow(stream) }
                ForEach(controller.folders) { folder in folderRow(folder) }
            }
            if !archivedStreams.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsArchive) {
                        ForEach(archivedStreams) { stream in streamRow(stream) }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                            .badge(archivedStreams.count)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Streams")
        .accessibilityIdentifier("workspace.sidebar")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()
                Menu {
                    Button("New Folder…", systemImage: "folder.badge.plus") { workspace.sheet = .newFolder }
                    Button("Show Library in Finder", systemImage: "folder") {
                        NSWorkspace.shared.open(controller.store.libraryRoot)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Library actions")
                .accessibilityLabel("Library actions")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear(perform: revealSelection)
        .onChange(of: controller.stream) { _, _ in revealSelection() }
    }

    private func folderRow(_ folder: StreamFolder) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { !workspace.collapsedFolders.contains(folder.id) },
            set: { expanded in
                if expanded { workspace.collapsedFolders.remove(folder.id) }
                else { workspace.collapsedFolders.insert(folder.id) }
            }
        )) {
            ForEach(visibleStreams.filter { $0.folderID == folder.id && !$0.isPinned }) { stream in streamRow(stream) }
        } label: {
            Label(folder.name, systemImage: "folder")
        }
        .contextMenu {
            Button("New Stream…", systemImage: "plus") { workspace.sheet = .newStream(folder.id) }
            Button("Rename Folder…") { workspace.sheet = .renameFolder(folder) }
            Button("Ungroup Folder") { controller.removeFolder(folder.id) }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let id = UUID(uuidString: value),
                  controller.streams.contains(where: { $0.id == id }) else { return false }
            controller.moveStream(id, to: folder.id)
            return true
        }
    }

    private func streamRow(_ stream: Stream) -> some View {
        Label(stream.name, systemImage: stream.slug == "daily" ? "calendar" : "book.closed")
            .lineLimit(1)
            .tag(Selection.stream(stream.id))
            .accessibilityIdentifier("stream.\(stream.id)")
            .help(stream.name)
            .draggable(stream.id.uuidString)
            .dropDestination(for: String.self) { items, _ in
                guard let value = items.first, let id = UUID(uuidString: value), id != stream.id,
                      controller.streams.contains(where: { $0.id == id }) else { return false }
                var ids = controller.streams.map(\.id).filter { $0 != id }
                guard let index = ids.firstIndex(of: stream.id) else { return false }
                ids.insert(id, at: index)
                controller.moveStream(id, to: stream.folderID)
                controller.reorderStreams(ids)
                return true
            }
            .contextMenu {
                Button("Open in Tab") { workspace.showsTabs = true; controller.openStreamTab(stream.id) }
                Button("Rename…") { workspace.sheet = .renameStream(stream) }
                Button(stream.isPinned ? "Unpin" : "Pin", systemImage: stream.isPinned ? "pin.slash" : "pin") {
                    controller.setStreamPinned(stream.id, isPinned: !stream.isPinned)
                }
                Menu("Move to Folder") {
                    Button("No Folder") { controller.moveStream(stream.id, to: nil) }
                    ForEach(controller.folders) { folder in
                        Button(folder.name) { controller.moveStream(stream.id, to: folder.id) }
                    }
                }
                Divider()
                if stream.isArchived {
                    Button("Restore Stream") { controller.restoreStream(stream.id) }
                } else {
                    Button("Archive Stream", systemImage: "archivebox") { controller.archiveStream(stream.id) }
                }
            }
    }

    private func revealSelection() {
        guard let stream = controller.stream else { return }
        if stream.isArchived { showsArchive = true }
        else if !stream.isPinned, let folderID = stream.folderID { workspace.collapsedFolders.remove(folderID) }
    }
}
