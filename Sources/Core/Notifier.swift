import Foundation
import UserNotifications

/// Posts native notifications on meaningful tunnel transitions (dropped, failed,
/// recovered). All side effects are gated behind `enabled` so tests never touch
/// the real notification center.
@MainActor
final class Notifier {
    private let enabled: Bool
    private var authorized = false

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func requestAuthorization() async {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func handleTransition(name: String, from previous: ForwardStatus, to next: ForwardStatus) async {
        guard enabled, authorized,
              let message = Notifier.message(name: name, from: previous, to: next)
        else { return }

        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Pure mapping from a status transition to notification copy (or nil for the
    /// many transitions we intentionally stay quiet about). Extracted so it can be
    /// unit-tested without the notification center.
    nonisolated static func message(
        name: String,
        from previous: ForwardStatus,
        to next: ForwardStatus
    ) -> (title: String, body: String)? {
        switch (previous, next) {
        case (.up, .reconnecting):
            return ("Connection dropped", "“\(name)” lost its connection and is reconnecting.")
        case (.reconnecting, .up):
            return ("Reconnected", "“\(name)” is back up.")
        case (_, .error(let detail)):
            // Only announce entering an error state, not error→error churn.
            if case .error = previous { return nil }
            return ("Forward failed", "“\(name)”: \(detail)")
        default:
            return nil
        }
    }
}
