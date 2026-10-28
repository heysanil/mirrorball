import AppKit

/// Hides the Dock icon when the last regular window closes (switching the app to
/// `.accessory`) and restores it when a regular window becomes main again. The
/// menu bar item and tunnels are unaffected. Opt-out via Settings.
@MainActor
final class DockPresenceController: NSObject {
    /// `UserDefaults` key for the Settings toggle. Defaults to `true` (hide).
    nonisolated static let hidesDockIconKey = "hideDockIconWhenWindowsClosed"

    /// Reads the preference, treating "never set" as the default (`true`).
    nonisolated static func hidesDockIcon(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: hidesDockIconKey) as? Bool ?? true
    }

    private let windows: () -> [NSWindow]
    private let hidesDockIcon: () -> Bool
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void

    init(
        notificationCenter: NotificationCenter,
        windows: @escaping () -> [NSWindow],
        hidesDockIcon: @escaping () -> Bool,
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void
    ) {
        self.windows = windows
        self.hidesDockIcon = hidesDockIcon
        self.setActivationPolicy = setActivationPolicy
        super.init()
        notificationCenter.addObserver(
            self, selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification, object: nil
        )
        notificationCenter.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil
        )
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              isRegularWindow(window) else { return }
        setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard hidesDockIcon(),
              let closingWindow = notification.object as? NSWindow,
              isRegularWindow(closingWindow) else { return }
        // `willClose` fires while the closing window is still visible, so exclude it.
        let hasOpenWindow = windows().contains { window in
            window !== closingWindow && isRegularWindow(window)
                && (window.isVisible || window.isMiniaturized)
        }
        if !hasOpenWindow {
            setActivationPolicy(.accessory)
        }
    }

    /// A titled, non-panel window. Deliberately not `canBecomeMain`: AppKit
    /// returns `false` for any non-visible window, which would make minimized
    /// windows invisible to the inventory check (and strand them when the Dock
    /// icon — and their Dock tile — disappears).
    private func isRegularWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled)
    }
}
