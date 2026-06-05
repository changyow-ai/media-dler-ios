import Foundation

/// One streamed progress event from an engine while it works through a window.
/// `partialText` is the cumulative text recognised so far in this window (for
/// live UI); the engine returns the window's final `Transcript` separately.
public struct StreamResult: Equatable {
    public let windowIndex: Int
    public let partialText: String
    public let isFinal: Bool

    public init(windowIndex: Int, partialText: String, isFinal: Bool) {
        self.windowIndex = windowIndex
        self.partialText = partialText
        self.isFinal = isFinal
    }
}

/// Abstraction over the recognition backend (whisper.cpp on-device, OpenRouter
/// cloud, future sherpa-onnx). Platform-neutral on purpose: input is 16kHz mono
/// Float32 PCM for a single planned window, so the decode/IO concerns live in
/// the app layer (`AudioToPCM`) and the engine only recognises.
///
/// `engineId` is recorded on the job's checkpoint; if the user switches engines
/// mid-job, a differing id forces a clean re-transcribe (windowing differs
/// between engines and seams would otherwise mismatch).
public protocol TranscriptionEngine: AnyObject {
    var engineId: String { get }

    /// Recognise one window of PCM. `onPartial` streams cumulative text for the
    /// live UI; the returned `Transcript` is this window's final raw text.
    /// Throwing aborts the window (and the job, surfacing the error).
    func transcribeWindow(
        pcm: [Float],
        window: TimeWindow,
        knownLanguage: TranscribeLanguage,
        onPartial: @escaping (StreamResult) -> Void
    ) async throws -> Transcript
}
