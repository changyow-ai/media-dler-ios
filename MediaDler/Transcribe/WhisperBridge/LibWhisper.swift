import Foundation

#if canImport(whisper)
import whisper

/// Swift wrapper over the whisper.cpp C API. Adapted from the official
/// `examples/whisper.swiftui/.../LibWhisper.swift` (trimmed to what we need).
/// Compiled only when the vendored `whisper.xcframework` is present — see
/// `scripts/build-whisper.sh` and the commented framework entry in project.yml.
enum WhisperError: Error { case couldNotInitializeContext }

actor WhisperContext {
    private var context: OpaquePointer

    private init(context: OpaquePointer) { self.context = context }

    deinit { whisper_free(context) }

    static func create(path: String) throws -> WhisperContext {
        var params = whisper_context_default_params()
        #if targetEnvironment(simulator)
        // No Metal in the simulator — force CPU so CI/sim builds run.
        params.use_gpu = false
        #endif
        guard let ctx = whisper_init_from_file_with_params(path, params) else {
            throw WhisperError.couldNotInitializeContext
        }
        return WhisperContext(context: ctx)
    }

    /// Runs whisper over one window of 16kHz mono Float32 PCM.
    /// - Parameter language: ISO code to lock recognition to, or nil for auto.
    /// - Returns: the window's raw text and the detected language code.
    func transcribe(samples: [Float], language: String?) -> (text: String, detectedLanguage: String?) {
        let threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.n_threads = threads
        params.offset_ms = 0
        params.no_context = true
        params.single_segment = false

        whisper_reset_timings(context)

        let result: (String, String?) = samples.withUnsafeBufferPointer { buf in
            func run() -> (String, String?) {
                guard whisper_full(context, params, buf.baseAddress, Int32(buf.count)) == 0 else {
                    return ("", nil)
                }
                return (collectText(), detectedLanguage())
            }
            if let language {
                return language.withCString { c -> (String, String?) in
                    params.language = c
                    params.detect_language = false
                    return run()
                }
            } else {
                params.language = nil
                params.detect_language = true
                return run()
            }
        }
        return result
    }

    private func collectText() -> String {
        var text = ""
        let n = whisper_full_n_segments(context)
        for i in 0..<n {
            if let cstr = whisper_full_get_segment_text(context, i) {
                text += String(cString: cstr)
            }
        }
        return text
    }

    private func detectedLanguage() -> String? {
        let id = whisper_full_lang_id(context)
        guard id >= 0, let cstr = whisper_lang_str(id) else { return nil }
        return String(cString: cstr)
    }
}
#endif
