import Foundation
import Testing
@testable import CurrentFeature

@Test @MainActor
func renameResultsReportPersistenceFailureAndPermitRetry() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-rename-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = StreamStore(libraryRoot: root)
    let controller = TimelineController(store: store)
    controller.bootstrapIfNeeded()
    let stream = try #require(controller.stream)
    let folder = try #require(controller.createFolder(name: "Work"))
    let manifest = try Data(contentsOf: store.manifestURL)
    let metadata = stream.rootURL.appendingPathComponent(store.metadataFilename)
    let savedMetadata = try Data(contentsOf: metadata)
    // A directory at the metadata destination fails writes on every machine,
    // including test runners whose privileges bypass read-only file modes.
    try FileManager.default.removeItem(at: metadata)
    try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: false)

    #expect(!controller.renameStream(stream.id, name: "Planning"))
    #expect(controller.stream?.name == stream.name)
    #expect(!controller.renameFolder(folder.id, name: "Projects"))
    #expect(controller.folders.first(where: { $0.id == folder.id })?.name == "Work")
    #expect(controller.notice?.kind == .saveError)
    #expect(try Data(contentsOf: store.manifestURL) == manifest)

    try FileManager.default.removeItem(at: metadata)
    try savedMetadata.write(to: metadata)
    #expect(controller.renameStream(stream.id, name: " Planning "))
    #expect(controller.renameFolder(folder.id, name: " Projects "))
    let reloaded = try store.loadLibrary()
    #expect(reloaded.streams.first(where: { $0.id == stream.id })?.name == "Planning")
    #expect(reloaded.folders.first(where: { $0.id == folder.id })?.name == "Projects")
}

@Test @MainActor
func invalidAndMissingRenameTargetsCannotReportSuccess() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("current-invalid-rename-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = TimelineController(store: StreamStore(libraryRoot: root))
    controller.bootstrapIfNeeded()
    let stream = try #require(controller.stream)
    let folder = try #require(controller.createFolder(name: "Work"))
    let manifest = try Data(contentsOf: controller.store.manifestURL)
    #expect(!controller.renameStream(stream.id, name: " \n"))
    #expect(!controller.renameFolder(folder.id, name: "\t"))
    #expect(!controller.renameStream(UUID(), name: "Missing"))
    #expect(!controller.renameFolder(UUID(), name: "Missing"))
    #expect(try Data(contentsOf: controller.store.manifestURL) == manifest)
}
