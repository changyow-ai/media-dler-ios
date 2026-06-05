import Foundation
import UniformTypeIdentifiers

/// A local media file the user shared into the app for transcription, already
/// copied into our private storage so the job can resume even after the system
/// reclaims the original (Inbox files / security-scoped URLs are transient).
struct LocalMedia: Identifiable, Equatable {
    let id: String
    /// Absolute file URL inside `Documents/transcribe/input/`.
    let url: URL
    let isVideo: Bool
    /// Display title — the original filename without extension.
    let title: String
}

/// Copies shared local files into a stable private location. The system hands
/// us either a security-scoped URL (Open-in-place) or a file dropped in
/// `Documents/Inbox/`; both must be moved into our own folder promptly.
enum LocalMediaInput {
    /// Root for copied transcription inputs (a resumable source per job).
    static var inputDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("transcribe/input", isDirectory: true)
    }

    /// Imports a shared `file://` URL into private storage. Returns a `LocalMedia`
    /// describing the stable copy, or nil if the file can't be read/copied.
    static func importFile(_ url: URL) -> LocalMedia? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        try? fm.createDirectory(at: inputDir, withIntermediateDirectories: true)

        let jobId = jobId(for: url)
        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let dest = inputDir.appendingPathComponent("\(jobId).\(ext)")

        // A prior copy for the same source means this job already exists —
        // reuse it (resumable). Otherwise copy the bytes in now.
        if !fm.fileExists(atPath: dest.path) {
            do {
                try fm.copyItem(at: url, to: dest)
            } catch {
                MDLog.log("LocalMediaInput.importFile: copy failed \(url.lastPathComponent): \(error)")
                return nil
            }
        }
        cleanInbox()

        return LocalMedia(
            id: jobId,
            url: dest,
            isVideo: isVideo(ext: ext),
            title: url.deletingPathExtension().lastPathComponent
        )
    }

    /// Adopts an already-downloaded local file (e.g. yt-dlp bestaudio for a
    /// shared link) into the resumable input dir. `jobKey` (the source URL)
    /// derives a stable job id so re-transcribing the same link resumes.
    static func adopt(localFile url: URL, jobKey: String, title: String) -> LocalMedia? {
        let fm = FileManager.default
        try? fm.createDirectory(at: inputDir, withIntermediateDirectories: true)
        let jobId = "link-" + stableHash(jobKey)
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let dest = inputDir.appendingPathComponent("\(jobId).\(ext)")
        if fm.fileExists(atPath: dest.path) {
            try? fm.removeItem(at: url) // already have a copy → drop the new temp
        } else {
            do { try fm.moveItem(at: url, to: dest) }
            catch {
                MDLog.log("LocalMediaInput.adopt: move failed: \(error)")
                return nil
            }
        }
        return LocalMedia(id: jobId, url: dest, isVideo: isVideo(ext: ext), title: title)
    }

    /// Stable job id derived from the source path so re-sharing the same file
    /// maps to the same resumable job (mirrors the Android "id from source").
    private static func jobId(for url: URL) -> String {
        return "local-" + stableHash(url.standardizedFileURL.path)
    }

    /// Deterministic FNV-1a 64-bit hex digest. Swift's `String.hashValue` is
    /// seeded per process, so it would give the SAME source a DIFFERENT id on
    /// each launch — breaking resume after the app is killed/relaunched. This
    /// is stable across processes.
    static func stableHash(_ s: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    /// True for video containers; false for audio-only. Uses UTType so it works
    /// across mp4/mov/m4a/mp3/wav/caf/… not just a fixed extension list.
    static func isVideo(ext: String) -> Bool {
        guard let type = UTType(filenameExtension: ext.lowercased()) else {
            // Fall back to a small extension list when UTType can't classify.
            return ["mp4", "mov", "m4v", "mkv", "webm", "avi"].contains(ext.lowercased())
        }
        if type.conforms(to: .audio) { return false }
        return type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }

    /// Inbox files must be moved out promptly; we've already copied what we
    /// need, so clear leftovers to reclaim space.
    private static func cleanInbox() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inbox = docs.appendingPathComponent("Inbox", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return }
        for item in items { try? FileManager.default.removeItem(at: item) }
    }
}
