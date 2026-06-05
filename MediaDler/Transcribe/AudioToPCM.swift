import Foundation
import AVFoundation
import MediaDlerCore

enum AudioToPCMError: LocalizedError {
    case noAudioTrack
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "這個檔案沒有可解析的音訊軌。"
        case .readerFailed(let why): return "音訊解碼失敗：\(why)"
        }
    }
}

/// Decodes arbitrary audio/video containers into 16kHz mono Float32 PCM using
/// the system `AVAssetReader` (no ffmpeg). Supports per-window decoding via
/// `timeRange` so a long file never loads its whole PCM at once — each window's
/// samples are produced, consumed by the engine, then released (the Android
/// `decodeRange` decision, ported).
enum AudioToPCM {
    static let sampleRate: Double = 16000

    /// Total duration in milliseconds.
    static func durationMs(of url: URL) async throws -> Int64 {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64((seconds * 1000).rounded())
    }

    /// Decode `[startMs, endMs)` into 16kHz mono Float32 PCM.
    static func decodeRange(url: URL, startMs: Int64, endMs: Int64) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioToPCMError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let start = CMTime(value: max(0, startMs), timescale: 1000)
        let end = CMTime(value: max(startMs + 1, endMs), timescale: 1000)
        reader.timeRange = CMTimeRange(start: start, end: end)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw AudioToPCMError.readerFailed("無法建立 PCM 輸出。")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw AudioToPCMError.readerFailed(reader.error?.localizedDescription ?? "未知錯誤")
        }

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            if let block = CMSampleBufferGetDataBuffer(buffer) {
                let length = CMBlockBufferGetDataLength(block)
                let count = length / MemoryLayout<Float>.size
                if count > 0 {
                    var chunk = [Float](repeating: 0, count: count)
                    chunk.withUnsafeMutableBytes { raw in
                        _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
                    }
                    samples.append(contentsOf: chunk)
                }
            }
            CMSampleBufferInvalidate(buffer)
        }

        if reader.status == .failed {
            throw AudioToPCMError.readerFailed(reader.error?.localizedDescription ?? "讀取中斷")
        }
        return samples
    }
}
