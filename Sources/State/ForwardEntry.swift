import Foundation
import Observation

/// Runtime wrapper around a persisted `Forward`: pairs the value with its live
/// status and the supervisor keeping it alive. Observable so SwiftUI updates the
/// moment a status changes.
@MainActor
@Observable
final class ForwardEntry: Identifiable {
    let id: UUID
    var forward: Forward
    var status: ForwardStatus = .off

    @ObservationIgnored var supervisor: TunnelSupervisor?
    @ObservationIgnored var statusTask: Task<Void, Never>?

    init(forward: Forward) {
        self.id = forward.id
        self.forward = forward
    }

    /// Whether a supervisor is currently attached and trying to keep it up.
    var isSupervised: Bool { supervisor != nil }
}
