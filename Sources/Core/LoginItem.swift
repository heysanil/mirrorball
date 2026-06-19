import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` — the modern login-item API that
/// self-registers the app to launch at login (no separate helper target needed).
///
/// Note: registration is reliable only for a properly signed app running from a
/// stable location (ideally `/Applications`). From DerivedData with ad-hoc
/// signing it may throw; callers surface that error rather than crashing.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else {
            if service.status == .enabled {
                try service.unregister()
            }
        }
    }
}
