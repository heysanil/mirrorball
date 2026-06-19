import AppKit

/// Handles app-lifecycle concerns SwiftUI doesn't express directly: tearing down
/// ssh children on quit, and keeping the app alive in the menu bar after its
/// window is closed (it's a menu-bar utility, not a single-window app).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ChildProcessRegistry.shared.terminateAll()
    }
}
