import Foundation
import UIKit
import UserNotifications

/// iOS has no foreground service. This wraps long work in a
/// `beginBackgroundTask` grace window so the in-flight window can finish and a
/// checkpoint can land when the user backgrounds the app, and posts a
/// completion/failure local notification. (The biggest structural difference
/// from the Android foreground-service design.)
@MainActor
final class TranscriptionRunner {
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    /// Acquire OS grace time so the current window finishes + checkpoints if the
    /// app is backgrounded mid-job.
    func beginGrace(name: String) {
        endGrace()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.endGrace()
        }
    }

    func endGrace() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
