import Foundation

/// Timing constants for the per-forward supervisor. Mirrors the original
/// Mirrorball values so reconnection behavior is identical.
enum SupervisorConstants {
    /// If `ssh` exits within this window of starting, treat it as a failure
    /// rather than a healthy connection (catches bind failures, bad hosts).
    static let grace: Duration = .milliseconds(1500)
    /// First reconnect delay after an unexpected drop.
    static let backoffStart: Duration = .seconds(1)
    /// Reconnect delay never grows past this.
    static let backoffMax: Duration = .seconds(30)
    /// A connection that stays up at least this long resets the backoff budget.
    static let stableAfter: Duration = .seconds(10)
}

extension Duration {
    /// Double a backoff duration without overflowing, capped at `max`.
    func doubled(upTo max: Duration) -> Duration {
        let next = self + self
        return next > max ? max : next
    }
}
