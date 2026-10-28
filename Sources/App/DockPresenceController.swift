import AppKit

@MainActor
final class DockPresenceController: NSObject {
    private let windows: () -> [NSWindow]
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void

    init(
        notificationCenter: NotificationCenter,
        windows: @escaping () -> [NSWindow],
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void
    ) {
        self.windows = windows
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
        guard let closingWindow = notification.object as? NSWindow,
              isRegularWindow(closingWindow) else { return }
        let hasOpenWindow = windows().contains { window in
            window !== closingWindow && isRegularWindow(window)
                && (window.isVisible || window.isMiniaturized)
        }
        if !hasOpenWindow {
            setActivationPolicy(.accessory)
        }
    }

    private func isRegularWindow(_ window: NSWindow) -> Bool {
        window.canBecomeMain && !(window is NSPanel)
    }
}
