import SwiftUI

@main
struct MirrorballApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Mirrorball", id: "manager") {
            ManagerWindow()
                .environment(model)
                .environment(delegate.updater)
                .task { model.performLaunchOnce() }
        }
        .defaultSize(width: Metrics.windowWidth, height: 560)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Forward") {
                    NotificationCenter.default.post(name: .mbNewForward, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            // Standard "Check for Updates…" item, directly under "About Mirrorball".
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    delegate.updater.checkForUpdates()
                }
                .disabled(!delegate.updater.canCheckForUpdates)
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .environment(delegate.updater)
                .task { model.performLaunchOnce() }
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(delegate.updater)
        }
    }
}

extension Notification.Name {
    /// Posted by the ⌘N menu command; the visible window opens the editor.
    static let mbNewForward = Notification.Name("co.sanil.mirrorball.newForward")
}
