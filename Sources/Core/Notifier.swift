import Foundation
import UserNotifications

/// Posts native notifications on meaningful tunnel transitions (dropped, failed,
/// recovered). All side effects are gated behind `enabled` so tests never touch
/// the real notification center.
///
/// Notifications are *debounced*: a forward that drops and recovers within
/// `settleDelay` produces nothing at all. Only an outage that outlasts the window
/// is announced, and a recovery is announced only if its outage was. This keeps a
/// tunnel that blips and self-heals (idle/NAT timeouts) from spamming the user.
@MainActor
final class Notifier {
    /// Notification copy. Returned by the pure `message(...)` mapping and handed to
    /// the delivery sink.
    struct Message: Equatable {
        let title: String
        let body: String
    }

    private let enabled: Bool
    /// How long a forward must stay troubled before its outage is announced (and
    /// how briefly it can blip while staying silent). Injectable for tests.
    private let settleDelay: Duration
    /// Delivery sink. Defaults to the system notification center (gated on
    /// authorization); tests inject a recorder.
    private let deliverOverride: (@MainActor (Message) -> Void)?
    private var authorized = false

    // Per-forward debounce state.
    /// Forwards that have reached `.up` at least once. A forward that has never
    /// connected can't "drop", so its initial connect never announces an outage.
    private var everUp: Set<UUID> = []
    /// Most recent troubled status, read when the outage timer fires to pick copy.
    private var latestTrouble: [UUID: ForwardStatus] = [:]
    /// Pending "announce this outage after the settle window" task, per forward.
    private var outageTimers: [UUID: Task<Void, Never>] = [:]
    /// Forwards whose outage we've actually announced (so we know to announce
    /// recovery, and not to re-announce while still down).
    private var announced: Set<UUID> = []

    init(
        enabled: Bool,
        settleDelay: Duration = .seconds(5),
        deliver: (@MainActor (Message) -> Void)? = nil
    ) {
        self.enabled = enabled
        self.settleDelay = settleDelay
        self.deliverOverride = deliver
    }

    func requestAuthorization() async {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Feed every status change here. A forward that drops and returns to `.up`
    /// within `settleDelay` produces no notification; only an outage that outlasts
    /// the window is announced.
    func handleStatus(id: UUID, name: String, status: ForwardStatus) {
        switch status {
        case .up:
            // Healthy. Any pending outage is now a non-event; cancel it. If we'd
            // already announced the outage, announce the recovery.
            outageTimers[id]?.cancel()
            outageTimers[id] = nil
            latestTrouble[id] = nil
            everUp.insert(id)
            if announced.remove(id) != nil {
                deliverMapped(name: name, from: .reconnecting, to: .up)
            }

        case .off:
            // User turned it off — forget everything, silently.
            forget(id: id)

        case .starting, .reconnecting, .error:
            latestTrouble[id] = status
            // A forward that has never come up is connecting for the first time,
            // not dropping — stay quiet.
            guard everUp.contains(id) else { return }
            // Already counting down or already announced this outage — don't
            // restart the clock or double-announce.
            guard outageTimers[id] == nil, !announced.contains(id) else { return }
            let delay = settleDelay
            outageTimers[id] = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                self.announceOutage(id: id, name: name)
            }
        }
    }

    /// Forget a forward's notification state (e.g. when it's turned off or deleted).
    func forget(id: UUID) {
        outageTimers[id]?.cancel()
        outageTimers[id] = nil
        latestTrouble[id] = nil
        announced.remove(id)
        everUp.remove(id)
    }

    /// The settle window elapsed and the forward is still troubled: announce it.
    private func announceOutage(id: UUID, name: String) {
        outageTimers[id] = nil
        announced.insert(id)
        // Choose copy from the current trouble: a real error reports the reason,
        // anything else (reconnecting/retrying) reads as a dropped connection.
        let trouble = latestTrouble[id] ?? .reconnecting
        let copyTo: ForwardStatus
        if case .error = trouble {
            copyTo = trouble
        } else {
            copyTo = .reconnecting
        }
        deliverMapped(name: name, from: .up, to: copyTo)
    }

    private func deliverMapped(name: String, from previous: ForwardStatus, to next: ForwardStatus) {
        if let copy = Notifier.message(name: name, from: previous, to: next) {
            deliver(Message(title: copy.title, body: copy.body))
        }
    }

    private func deliver(_ message: Message) {
        if let deliverOverride {
            deliverOverride(message)
            return
        }
        guard enabled, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
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
