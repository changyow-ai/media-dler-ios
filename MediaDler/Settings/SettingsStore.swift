import Foundation
import Combine
import MediaDlerCore

/// Persists `AppSettings` as JSON in UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    private static let key = "appSettings"

    @Published var settings: AppSettings {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
