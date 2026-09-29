import Foundation
import Testing
@testable import Wheedgets
@testable import WheedgetsCore

@MainActor
struct KeyPackLibraryTests {
    private let workspace = FileManager.default.temporaryDirectory.appending(path: "WheedgetsLibraryTests-\(UUID().uuidString)")

    private func makePack(named name: String) throws -> URL {
        let folder = workspace.appending(path: "source/\(name)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = #"{"name": "\#(name)", "key_define_type": "multi", "defines": {"30": "a.wav"}}"#
        try Data(config.utf8).write(to: folder.appending(path: "config.json"))
        try Data("RIFF".utf8).write(to: folder.appending(path: "a.wav"))
        return folder
    }

    @Test func importsAFolderAndListsIt() throws {
        defer { try? FileManager.default.removeItem(at: workspace) }
        let library = KeyPackLibrary(directory: workspace.appending(path: "library"))

        let installed = try library.importPack(from: makePack(named: "Folder Pack"))

        #expect(installed.name == "Folder Pack")
        #expect(library.installedPacks() == [installed])
        library.remove(installed.folder)
        #expect(library.installedPacks().isEmpty)
    }

    @Test func importsAZipWithTheFolderInside() throws {
        defer { try? FileManager.default.removeItem(at: workspace) }
        let library = KeyPackLibrary(directory: workspace.appending(path: "library"))
        let folder = try makePack(named: "Zipped Pack")
        let archive = workspace.appending(path: "pack.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--keepParent", folder.path, archive.path]
        try zip.run()
        zip.waitUntilExit()

        let installed = try library.importPack(from: archive)

        #expect(installed.name == "Zipped Pack")
        #expect(FileManager.default.fileExists(atPath: library.folderURL(installed.folder).appending(path: "a.wav").path))
    }

    @Test func rejectsFoldersWithoutAPack() throws {
        defer { try? FileManager.default.removeItem(at: workspace) }
        let library = KeyPackLibrary(directory: workspace.appending(path: "library"))
        let empty = workspace.appending(path: "empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        #expect(throws: KeyPackLibrary.ImportError.self) { try library.importPack(from: empty) }
    }
}
