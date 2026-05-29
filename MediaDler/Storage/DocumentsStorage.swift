import Foundation

/// Saves audio (and other non-Photos) files into the app's Documents folder,
/// which is exposed to the Files app via UIFileSharingEnabled +
/// LSSupportsOpeningDocumentsInPlace. (Video/images are handled by the
/// library's Photos export.)
enum DocumentsStorage {
    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("media-dler", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies `source` into the media-dler folder, de-duplicating the name
    /// rather than overwriting an existing file.
    @discardableResult
    static func save(_ source: URL, preferredName: String) -> URL? {
        let ext = source.pathExtension
        let base = sanitize(preferredName)
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(n))").appendingPathExtension(ext)
            n += 1
        }
        do {
            try FileManager.default.copyItem(at: source, to: candidate)
            return candidate
        } catch {
            print("DocumentsStorage save failed: \(error)")
            return nil
        }
    }

    private static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "media" : String(trimmed.prefix(80))
    }
}
