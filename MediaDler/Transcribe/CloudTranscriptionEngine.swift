import Foundation
import MediaDlerCore

/// Cloud transcription via OpenRouter (`POST /audio/transcriptions`, JSON +
/// base64). Contract is identical to the Android engine: billed by audio
/// duration (not bytes), no language field in the response, no timestamps.
/// Windows are capped by the planner (WAV 5min) because the upstream has a
/// ~60s timeout and base64 inflates the payload.
final class CloudTranscriptionEngine: TranscriptionEngine {
    let engineId: String
    private let apiKey: String
    private let baseUrl: String
    private let model: String

    init(apiKey: String, baseUrl: String, model: String) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.model = model
        self.engineId = "openrouter-\(model)"
    }

    func transcribeWindow(
        pcm: [Float],
        window: TimeWindow,
        knownLanguage: TranscribeLanguage,
        onPartial: @escaping (StreamResult) -> Void
    ) async throws -> Transcript {
        let wav = WavEncoder.encode(pcm: pcm)
        var body: [String: Any] = [
            "model": model,
            "input_audio": ["format": "wav", "data": wav.base64EncodedString()],
        ]
        // language省略則自動偵測；鎖定語言時帶上（也是正體 caveat 的解法）。
        if knownLanguage != .auto { body["language"] = knownLanguage.rawValue }

        let trimmed = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        guard let url = URL(string: trimmed + "/audio/transcriptions") else {
            throw TranscribeError.message("雲端 base URL 無效：\(baseUrl)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 120

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw TranscribeError.message("雲端轉錄沒有有效回應。")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?.prefix(400) ?? ""
            throw TranscribeError.message("雲端轉錄失敗（HTTP \(http.statusCode)）：\(detail)")
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = (json?["text"] as? String) ?? ""
        onPartial(StreamResult(windowIndex: window.index, partialText: text, isFinal: true))
        // Cloud returns no `language` → nil (drives the 正體 caveat: lock zh to convert).
        return Transcript(text: text, detectedLanguage: nil)
    }
}
