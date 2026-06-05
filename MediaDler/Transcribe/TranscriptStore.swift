import Foundation

/// JSON-file persistence for transcription jobs (mirrors HistoryStore — no DB).
/// Written only at window checkpoints and terminal states, never on every
/// high-frequency progress tick (those stay in memory).
enum TranscriptStore {
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("transcripts.json")
    }

    static func load() -> [TranscriptJob] {
        guard let data = try? Data(contentsOf: fileURL),
              let jobs = try? JSONDecoder().decode([TranscriptJob].self, from: data) else {
            return []
        }
        return jobs
    }

    static func save(_ jobs: [TranscriptJob]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: fileURL)
    }
}
