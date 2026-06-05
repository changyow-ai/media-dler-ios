import Foundation
import MediaDlerCore

// sherpa-onnx is integrated via a vendored Swift wrapper + Objective-C bridging
// header (NOT a Swift module), so `canImport` can't gate it. Instead a custom
// compile flag `SHERPA_ONNX_ENABLED` (set in project.yml only when the vendored
// xcframeworks + wrapper are present) gates the engine. The app builds fine
// without it; the factory just returns nil → "engine not built".

#if SHERPA_ONNX_ENABLED
/// On-device `TranscriptionEngine` backed by sherpa-onnx (ONNX Runtime).
/// Recognizer is created lazily on the first window and reused. SenseVoice and
/// Qwen3 report a language; Paraformer is Chinese-only (we report "zh").
///
/// Wrapper symbols (`SherpaOnnxOfflineRecognizer`, `sherpaOnnxOfflineModelConfig`,
/// …) come from the vendored `SherpaOnnx.swift`; signatures are sensitive to the
/// sherpa-onnx version pinned by scripts/fetch-sherpa-libs.sh (v1.13.2).
final class SherpaOnnxEngine: TranscriptionEngine {
    let engineId: String
    private let model: TranscribeModel
    private let dir: String
    private var recognizer: SherpaOnnxOfflineRecognizer?

    init(model: TranscribeModel, modelDir: URL) {
        self.model = model
        self.dir = modelDir.path
        self.engineId = "sherpa-\(model.rawValue)"
    }

    func transcribeWindow(
        pcm: [Float],
        window: TimeWindow,
        knownLanguage: TranscribeLanguage,
        onPartial: @escaping (StreamResult) -> Void
    ) async throws -> Transcript {
        let rec = try recognizerOrCreate(knownLanguage: knownLanguage)
        let result = rec.decode(samples: pcm, sampleRate: 16000)
        let text = result.text
        onPartial(StreamResult(windowIndex: window.index, partialText: text, isFinal: true))
        let detected = detectedLanguage(from: result)
        return Transcript(text: text, detectedLanguage: detected)
    }

    private func recognizerOrCreate(knownLanguage: TranscribeLanguage) throws -> SherpaOnnxOfflineRecognizer {
        if let recognizer { return recognizer }
        var config = makeConfig(knownLanguage: knownLanguage)
        let rec = SherpaOnnxOfflineRecognizer(config: &config)
        recognizer = rec
        return rec
    }

    private func makeConfig(knownLanguage: TranscribeLanguage) -> SherpaOnnxOfflineRecognizerConfig {
        let tokens = "\(dir)/tokens.txt"
        let modelConfig: SherpaOnnxOfflineModelConfig
        switch model {
        case .senseVoice:
            // SenseVoice can lock a language; pass the user's choice (or "" auto).
            let lang = (knownLanguage == .auto) ? "" : knownLanguage.rawValue
            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: tokens,
                numThreads: 2,
                provider: "cpu",
                senseVoice: sherpaOnnxOfflineSenseVoiceModelConfig(
                    model: "\(dir)/model.int8.onnx",
                    language: lang,
                    useInverseTextNormalization: true
                )
            )
        case .paraformer:
            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: tokens,
                paraformer: sherpaOnnxOfflineParaformerModelConfig(model: "\(dir)/model.int8.onnx"),
                numThreads: 2,
                provider: "cpu",
                modelType: "paraformer"
            )
        case .qwen3:
            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: tokens,
                numThreads: 2,
                provider: "cpu",
                qwen3Asr: sherpaOnnxOfflineQwen3ASRModelConfig(
                    convFrontend: "\(dir)/conv-frontend.onnx",
                    encoder: "\(dir)/encoder.int8.onnx",
                    decoder: "\(dir)/decoder.int8.onnx",
                    tokenizer: tokens
                )
            )
        default:
            modelConfig = sherpaOnnxOfflineModelConfig(tokens: tokens, numThreads: 2, provider: "cpu")
        }
        return sherpaOnnxOfflineRecognizerConfig(
            featConfig: sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80),
            modelConfig: modelConfig
        )
    }

    private func detectedLanguage(from result: SherpaOnnxOfflineRecognizerResult) -> String? {
        // Paraformer is Chinese-only and reports no language → fix to zh so the
        // OpenCC traditional pass always runs.
        if model == .paraformer { return "zh" }
        let lang = result.lang.trimmingCharacters(in: CharacterSet(charactersIn: "<|> "))
        return lang.isEmpty ? nil : lang
    }
}
#endif

/// Builds the sherpa engine, or returns nil when sherpa isn't compiled in
/// (the `SHERPA_ONNX_ENABLED` flag is off → vendored libs not wired yet).
enum SherpaEngineFactory {
    static func engine(model: TranscribeModel, modelDir: URL) -> TranscriptionEngine? {
        #if SHERPA_ONNX_ENABLED
        return SherpaOnnxEngine(model: model, modelDir: modelDir)
        #else
        _ = (model, modelDir)
        return nil
        #endif
    }
}
