import Foundation
import MediaDlerCore

/// Persists completed/failed download tasks as JSON in Documents (no DB,
/// matching the Android HistoryStore approach).
enum HistoryStore {
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("history.json")
    }

    static func load() -> [DownloadTask] {
        guard let data = try? Data(contentsOf: fileURL),
              let tasks = try? JSONDecoder().decode([DownloadTask].self, from: data) else {
            return []
        }
        return tasks
    }

    static func save(_ tasks: [DownloadTask]) {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: fileURL)
    }
}
