import AppKit

/// Handles app-lifecycle concerns SwiftUI doesn't express directly: tearing down
/// ssh children on quit, keeping the app alive in the menu bar after its window
/// is closed (it's a menu-bar utility, not a single-window app), and owning the
/// auto-updater.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The single auto-updater, created once for the app's lifetime and injected
    /// into the SwiftUI environment. Disabled (a hard no-op) under tests and the
    /// `MIRRORBALL_DISABLE_UPDATER` / side-effects seams.
    let updater = Updater(enabled: !AppConfiguration.fromEnvironment().disableUpdater)

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ChildProcessRegistry.shared.terminateAll()
    }
}
