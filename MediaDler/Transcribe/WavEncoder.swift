import Foundation

/// Encodes 16kHz mono Float32 PCM into a standard 16-bit PCM WAV container for
/// the cloud (OpenRouter) `input_audio` payload (`format: "wav"`). WAV is the
/// only cloud upload format — lossless and well-supported by every model.
/// OpenRouter bills by audio duration (not bytes), so compressing the upload
/// would only save bandwidth, never cost; it's deliberately not implemented.
enum WavEncoder {
    static func encode(pcm: [Float], sampleRate: Int = 16000) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        // Float [-1, 1] → 16-bit signed little-endian.
        var samples16 = [Int16](repeating: 0, count: pcm.count)
        for i in pcm.indices {
            let clamped = max(-1.0, min(1.0, pcm[i]))
            samples16[i] = Int16(clamped * 32767.0)
        }
        let dataBytes = samples16.withUnsafeBufferPointer { Data(buffer: $0) }
        let dataSize = dataBytes.count

        var out = Data(capacity: 44 + dataSize)
        func append(_ string: String) { out.append(string.data(using: .ascii)!) }
        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
        }

        append("RIFF")
        appendLE(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        appendLE(UInt32(16))                 // PCM fmt chunk size
        appendLE(UInt16(1))                  // audio format = PCM
        appendLE(UInt16(channels))
        appendLE(UInt32(sampleRate))
        appendLE(UInt32(byteRate))
        appendLE(UInt16(blockAlign))
        appendLE(UInt16(bitsPerSample))
        append("data")
        appendLE(UInt32(dataSize))
        out.append(dataBytes)
        return out
    }
}
