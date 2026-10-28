import AppKit
import Testing
@testable import Mirrorball

@Suite("Dock presence follows regular windows")
@MainActor
struct DockPresenceControllerTests {
    @Test("Closing the last window hides the Dock icon even before it becomes invisible")
    func closingLastWindow() {
        let window = TestWindow()
        let context = Context(windows: [window])
        context.post(NSWindow.willCloseNotification, window: window)
        #expect(context.policies == [.accessory])
    }

    @Test("Closing one window keeps the Dock icon while another regular window is open")
    func anotherWindowIsOpen() {
        let window = TestWindow()
        let context = Context(windows: [window, TestWindow()])
        context.post(NSWindow.willCloseNotification, window: window)
        #expect(context.policies.isEmpty)
    }

    @Test("A minimized window keeps the Dock icon")
    func anotherWindowIsMinimized() {
        let window = TestWindow()
        let minimized = TestWindow()
        minimized.reportsVisible = false
        minimized.reportsMiniaturized = true
        // Regression guard: like AppKit, the fake reports `canBecomeMain == false`
        // once it's not visible, so the controller must not rely on it.
        #expect(!minimized.canBecomeMain)
        let context = Context(windows: [window, minimized])
        context.post(NSWindow.willCloseNotification, window: window)
        #expect(context.policies.isEmpty)
    }

    @Test("Hidden windows, untitled windows, and menu-bar panels do not keep the Dock icon")
    func hiddenWindowsAndPanels() {
        let window = TestWindow()
        let hidden = TestWindow()
        hidden.reportsVisible = false
        let borderless = TestWindow(styleMask: .borderless)
        let context = Context(windows: [window, hidden, borderless, TestPanel()])
        context.post(NSWindow.willCloseNotification, window: window)
        #expect(context.policies == [.accessory])
    }

    @Test("Reopening a regular window restores the Dock icon")
    func reopeningWindow() {
        let window = TestWindow()
        let context = Context(windows: [window])
        context.post(NSWindow.willCloseNotification, window: window)
        context.post(NSWindow.didBecomeMainNotification, window: window)
        #expect(context.policies == [.accessory, .regular])
    }

    @Test("Opening or closing a panel does not change Dock presence")
    func panelDoesNotChangePolicy() {
        let panel = TestPanel()
        let context = Context(windows: [panel])
        context.post(NSWindow.didBecomeMainNotification, window: panel)
        context.post(NSWindow.willCloseNotification, window: panel)
        #expect(context.policies.isEmpty)
    }

    @Test("With the setting off, closing the last window keeps the Dock icon")
    func settingDisabled() {
        let window = TestWindow()
        let context = Context(windows: [window], hidesDockIcon: false)
        context.post(NSWindow.willCloseNotification, window: window)
        #expect(context.policies.isEmpty)
    }

    @Test("The preference defaults to hiding and honours an explicit opt-out")
    func preferenceDefault() throws {
        let suite = "co.sanil.mirrorball.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DockPresenceController.hidesDockIcon(in: defaults))
        defaults.set(false, forKey: DockPresenceController.hidesDockIconKey)
        #expect(!DockPresenceController.hidesDockIcon(in: defaults))
    }

    /// Models AppKit's real behaviour: `canBecomeMain` is only true while visible.
    private final class TestWindow: NSWindow {
        var reportsVisible = true
        var reportsMiniaturized = false
        override var isVisible: Bool { reportsVisible }
        override var isMiniaturized: Bool { reportsMiniaturized }
        override var canBecomeMain: Bool { reportsVisible }

        init(styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]) {
            super.init(contentRect: .zero, styleMask: styleMask, backing: .buffered, defer: true)
        }
    }

    private final class TestPanel: NSPanel {
        override var isVisible: Bool { true }
        init() {
            super.init(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        }
    }

    @MainActor
    private final class Context {
        let notificationCenter = NotificationCenter()
        var policies: [NSApplication.ActivationPolicy] = []
        var controller: DockPresenceController!

        init(windows: [NSWindow], hidesDockIcon: Bool = true) {
            controller = DockPresenceController(
                notificationCenter: notificationCenter,
                windows: { windows },
                hidesDockIcon: { hidesDockIcon },
                setActivationPolicy: { [weak self] in self?.policies.append($0) }
            )
        }

        func post(_ name: Notification.Name, window: NSWindow) {
            notificationCenter.post(name: name, object: window)
        }
    }
}
