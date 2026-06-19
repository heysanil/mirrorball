import SwiftUI

@main
struct MirrorballApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Mirrorball", id: "manager") {
            ManagerWindow()
                .environment(model)
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
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .task { model.performLaunchOnce() }
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    /// Posted by the ⌘N menu command; the visible window opens the editor.
    static let mbNewForward = Notification.Name("co.sanil.mirrorball.newForward")
}
