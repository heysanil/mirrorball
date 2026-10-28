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
        let context = Context(windows: [window, minimized])
        context.post(NSWindow.willCloseNotification, window: window)
        #expect(context.policies.isEmpty)
    }

    @Test("Hidden windows and menu-bar panels do not keep the Dock icon")
    func hiddenWindowsAndPanels() {
        let window = TestWindow()
        let hidden = TestWindow()
        hidden.reportsVisible = false
        let context = Context(windows: [window, hidden, TestPanel()])
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

    @Test("Minimizing a window does not hide the Dock icon")
    func minimizingWindow() {
        let window = TestWindow()
        let context = Context(windows: [window])
        context.post(NSWindow.didMiniaturizeNotification, window: window)
        #expect(context.policies.isEmpty)
    }

    private final class TestWindow: NSWindow {
        var reportsVisible = true
        var reportsMiniaturized = false
        override var isVisible: Bool { reportsVisible }
        override var isMiniaturized: Bool { reportsMiniaturized }
        override var canBecomeMain: Bool { true }
    }

    private final class TestPanel: NSPanel {
        override var isVisible: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    @MainActor
    private final class Context {
        let notificationCenter = NotificationCenter()
        var policies: [NSApplication.ActivationPolicy] = []
        var controller: DockPresenceController!

        init(windows: [NSWindow]) {
            controller = DockPresenceController(
                notificationCenter: notificationCenter,
                windows: { windows },
                setActivationPolicy: { [weak self] in self?.policies.append($0) }
            )
        }

        func post(_ name: Notification.Name, window: NSWindow) {
            notificationCenter.post(name: name, object: window)
        }
    }
}
