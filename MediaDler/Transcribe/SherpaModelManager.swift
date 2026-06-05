import Foundation
import MediaDlerCore
#if canImport(SWCompression)
import SWCompression
#endif

/// Describes one sherpa-onnx model: its `.tar.bz2` release asset and the files
/// the recognizer needs after extraction.
struct SherpaModelSpec {
    /// Release asset basename (without `.tar.bz2`); also the extracted top dir.
    let archiveName: String
    /// Relative paths (inside the extracted dir) that must exist when done.
    let requiredFiles: [String]

    static func spec(for model: TranscribeModel) -> SherpaModelSpec? {
        switch model {
        case .senseVoice:
            return SherpaModelSpec(
                archiveName: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17",
                requiredFiles: ["model.int8.onnx", "tokens.txt"]
            )
        case .paraformer:
            return SherpaModelSpec(
                archiveName: "sherpa-onnx-paraformer-zh-int8-2025-10-07",
                requiredFiles: ["model.int8.onnx", "tokens.txt"]
            )
        case .qwen3:
            return SherpaModelSpec(
                archiveName: "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25",
                requiredFiles: ["encoder.int8.onnx", "decoder.int8.onnx"]
            )
        case .base, .small, .turboQ5:
            return nil // whisper.cpp models
        }
    }

    var url: URL {
        URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(archiveName).tar.bz2")!
    }
}

enum SherpaModelError: LocalizedError {
    case notSherpaModel
    case decompressUnavailable
    case extractFailed(String)
    case missingFiles([String])

    var errorDescription: String? {
        switch self {
        case .notSherpaModel: return "這不是 sherpa 模型。"
        case .decompressUnavailable: return "缺少 tar.bz2 解壓元件（SWCompression）。"
        case .extractFailed(let why): return "模型解壓失敗：\(why)"
        case .missingFiles(let f): return "模型檔不完整，缺少：\(f.joined(separator: ", "))"
        }
    }
}

/// Downloads + on-device extracts sherpa-onnx `.tar.bz2` models into
/// `Application Support/SherpaModels/<archiveName>/` (mirrors WhisperModelManager;
/// HF has no per-file mirror for these, hence tar.bz2). Models are NOT bundled.
@MainActor
final class SherpaModelManager: NSObject, ObservableObject {
    static let shared = SherpaModelManager()

    @Published private(set) var activeDownload: TranscribeModel?
    @Published private(set) var progress: Double = 0

    private var continuation: CheckedContinuation<URL, Error>?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    static var modelsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SherpaModels", isDirectory: true)
    }

    static func modelDir(for model: TranscribeModel) -> URL? {
        guard let spec = SherpaModelSpec.spec(for: model) else { return nil }
        return modelsDir.appendingPathComponent(spec.archiveName, isDirectory: true)
    }

    static func isDownloaded(_ model: TranscribeModel) -> Bool {
        guard let spec = SherpaModelSpec.spec(for: model), let dir = modelDir(for: model) else { return false }
        return spec.requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    /// Ensures the model is present (download + extract if needed); returns the
    /// model directory. Reuses `WhisperModelManager.isExpensiveNetwork()` gate.
    @discardableResult
    func ensureDownloaded(_ model: TranscribeModel) async throws -> URL {
        guard let spec = SherpaModelSpec.spec(for: model), let dir = Self.modelDir(for: model) else {
            throw SherpaModelError.notSherpaModel
        }
        if Self.isDownloaded(model) { return dir }
        guard activeDownload == nil else { throw TranscribeError.busy("已有模型正在下載。") }

        activeDownload = model
        progress = 0
        defer { activeDownload = nil }

        try? FileManager.default.createDirectory(at: Self.modelsDir, withIntermediateDirectories: true)

        let archive: URL = try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            session.downloadTask(with: spec.url).resume()
        }
        defer { try? FileManager.default.removeItem(at: archive) }

        try await extract(archive: archive, spec: spec, into: dir)
        let missing = spec.requiredFiles.filter {
            !FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        guard missing.isEmpty else { throw SherpaModelError.missingFiles(missing) }
        return dir
    }

    func delete(_ model: TranscribeModel) {
        guard let dir = Self.modelDir(for: model) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Decompresses the bzip2 tar and writes the entries flat into `dir`,
    /// stripping the archive's top-level folder.
    private func extract(archive: URL, spec: SherpaModelSpec, into dir: URL) async throws {
        #if canImport(SWCompression)
        let raw = try Data(contentsOf: archive)
        let tarData: Data
        do { tarData = try BZip2.decompress(data: raw) }
        catch { throw SherpaModelError.extractFailed("bzip2: \(error)") }
        let entries: [TarEntry]
        do { entries = try TarContainer.open(container: tarData) }
        catch { throw SherpaModelError.extractFailed("tar: \(error)") }

        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let prefix = spec.archiveName + "/"
        for entry in entries {
            guard entry.info.type == .regular, let data = entry.data else { continue }
            var name = entry.info.name
            if name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
            if name.isEmpty { continue }
            let dest = dir.appendingPathComponent(name)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest)
        }
        #else
        throw SherpaModelError.decompressUnavailable
        #endif
    }
}

extension SherpaModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tar.bz2")
        try? FileManager.default.moveItem(at: location, to: staged)
        Task { @MainActor in
            self.continuation?.resume(returning: staged)
            self.continuation = nil
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.progress = p }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
        }
    }
}
