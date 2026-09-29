import Foundation
import OSLog
import WheedgetsCore

struct InstalledKeyPack: Identifiable, Hashable {
    /// Folder name inside the library.
    let folder: String
    let name: String

    var id: KeyPackID { .imported(folder) }
}

/// Imported Mechvibes packs, each copied into its own folder in Application
/// Support, so a pack keeps working after the original is moved or deleted.
@MainActor
final class KeyPackLibrary {
    enum ImportError: LocalizedError {
        case noConfig
        case missingSounds
        case unzipFailed

        var errorDescription: String? {
            switch self {
            case .noConfig:
                String(localized: "No config.json found. Choose a Mechvibes sound pack folder or its .zip file.")
            case .missingSounds:
                String(localized: "The pack's sound files are missing.")
            case .unzipFailed:
                String(localized: "The .zip file could not be extracted.")
            }
        }
    }

    let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "Wheedgets", directoryHint: .isDirectory)
            .appending(path: "KeyboardPacks", directoryHint: .isDirectory)
    }

    func folderURL(_ folder: String) -> URL {
        directory.appending(path: folder, directoryHint: .isDirectory)
    }

    func installedPacks() -> [InstalledKeyPack] {
        let folders = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return folders.compactMap { folder in
            let config = folderURL(folder).appending(path: "config.json")
            guard let data = try? Data(contentsOf: config),
                  let pack = try? KeySoundPack.parseMechvibes(data) else { return nil }
            return InstalledKeyPack(folder: folder, name: pack.name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Accepts a pack folder, a folder that contains one, or a .zip of either.
    func importPack(from url: URL) throws -> InstalledKeyPack {
        let staging = fileManager.temporaryDirectory.appending(path: "WheedgetsImport-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staging) }

        var source = url
        if url.pathExtension.lowercased() == "zip" {
            try unzip(url, to: staging)
            source = staging
        }
        guard let root = findPackRoot(in: source) else { throw ImportError.noConfig }

        let pack = try KeySoundPack.parseMechvibes(Data(contentsOf: root.appending(path: "config.json")))
        let present = pack.referencedFiles.filter { fileManager.fileExists(atPath: root.appending(path: $0).path) }
        guard !present.isEmpty else { throw ImportError.missingSounds }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let folder = UUID().uuidString
        try fileManager.copyItem(at: root, to: folderURL(folder))
        return InstalledKeyPack(folder: folder, name: pack.name)
    }

    func remove(_ folder: String) {
        do {
            try fileManager.removeItem(at: folderURL(folder))
        } catch {
            Logger.audio.error("Could not remove pack \(folder): \(error.localizedDescription)")
        }
    }

    /// The folder holding config.json: the chosen folder itself, or a few levels down
    /// (zips often wrap the pack in a folder, sometimes next to a __MACOSX folder).
    private func findPackRoot(in folder: URL) -> URL? {
        if fileManager.fileExists(atPath: folder.appending(path: "config.json").path) { return folder }
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "__MACOSX" {
                enumerator.skipDescendants()
            } else if enumerator.level > 3 {
                enumerator.skipDescendants()
            } else if url.lastPathComponent == "config.json" {
                return url.deletingLastPathComponent()
            }
        }
        return nil
    }

    private func unzip(_ archive: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ImportError.unzipFailed }
    }
}
