import Foundation
import UserNotifications

enum TaskCompletionNotifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(_ result: TaskResult) {
        let content = UNMutableNotificationContent()
        content.title = result.title
        content.body = result.detail
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "easyzip.task.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
