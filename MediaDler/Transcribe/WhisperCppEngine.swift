import Foundation
import MediaDlerCore

#if canImport(whisper)
/// On-device `TranscriptionEngine` backed by whisper.cpp. The model context is
/// created lazily on the first window and reused across windows of the same job
/// (model load is expensive). Compiled only when the vendored framework exists.
final class WhisperCppEngine: TranscriptionEngine {
    let engineId: String
    private let modelPath: String
    private var context: WhisperContext?

    init(modelPath: String, modelLabel: String) {
        self.modelPath = modelPath
        self.engineId = "whispercpp-\(modelLabel)"
    }

    func transcribeWindow(
        pcm: [Float],
        window: TimeWindow,
        knownLanguage: TranscribeLanguage,
        onPartial: @escaping (StreamResult) -> Void
    ) async throws -> Transcript {
        let ctx: WhisperContext
        if let context {
            ctx = context
        } else {
            ctx = try WhisperContext.create(path: modelPath)
            context = ctx
        }
        let lang: String? = (knownLanguage == .auto) ? nil : knownLanguage.rawValue
        let (text, detected) = await ctx.transcribe(samples: pcm, language: lang)
        onPartial(StreamResult(windowIndex: window.index, partialText: text, isFinal: true))
        return Transcript(text: text, detectedLanguage: detected)
    }
}
#endif

/// Builds the configured on-device engine, or returns nil when the whisper
/// framework hasn't been vendored in yet (the app still runs; the job fails
/// with a clear "build the engine" message).
enum TranscriptionEngineFactory {
    static func onDeviceEngine(model: TranscribeModel, modelPath: String) -> TranscriptionEngine? {
        #if canImport(whisper)
        return WhisperCppEngine(modelPath: modelPath, modelLabel: model.rawValue)
        #else
        _ = (model, modelPath)
        return nil
        #endif
    }
}
