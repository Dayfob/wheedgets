import Foundation
import WheedgetsCore
import OSLog

/// Imported samples are copied into Application Support, so a pad keeps working
/// after the original file is moved or deleted.
@MainActor
final class SampleLibrary {
    enum ImportError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            String(localized: "This file can't be played. Choose a WAV, AIFF, MP3, M4A or CAF file.")
        }
    }

    let directory: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = Bundle.main.bundleIdentifier ?? "Wheedgets"
        directory = support.appending(path: appFolder, directoryHint: .isDirectory)
            .appending(path: "Samples", directoryHint: .isDirectory)
    }

    func url(for fileName: String) -> URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    func importSample(from url: URL) throws -> SoundSource {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard SampleDecoder.canDecode(url) else { throw ImportError.unreadable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "audio" : url.pathExtension.lowercased()
        let fileName = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: url, to: self.url(for: fileName))
        return .sample(fileName: fileName, displayName: url.deletingPathExtension().lastPathComponent)
    }

    /// Deletes copies no pad refers to any more.
    func removeUnused(keeping referenced: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where !referenced.contains(file) {
            do {
                try FileManager.default.removeItem(at: url(for: file))
            } catch {
                Logger.audio.error("Could not remove unused sample \(file): \(error.localizedDescription)")
            }
        }
    }
}
