import Foundation

/// Live state of a forward's connection, reported by its supervisor.
///
/// Never serialized — it is rebuilt from scratch each run.
enum ForwardStatus: Sendable, Equatable {
    /// Not running.
    case off
    /// `ssh` spawned, inside the grace window before we trust it.
    case starting
    /// Connection believed healthy.
    case up
    /// Dropped unexpectedly; waiting out the backoff before respawning.
    case reconnecting
    /// `ssh` failed; the string is the last stderr line (e.g. a bind failure).
    case error(String)

    /// True while a supervisor is attached and trying to keep the tunnel alive.
    var isActive: Bool {
        switch self {
        case .off: false
        case .starting, .up, .reconnecting, .error: true
        }
    }

    /// Short label for compact surfaces (menu bar, accessibility).
    var shortLabel: String {
        switch self {
        case .off: "Off"
        case .starting: "Connecting"
        case .up: "Connected"
        case .reconnecting: "Reconnecting"
        case .error: "Error"
        }
    }

    /// The error text, if any.
    var errorMessage: String? {
        if case let .error(message) = self { return message }
        return nil
    }
}
