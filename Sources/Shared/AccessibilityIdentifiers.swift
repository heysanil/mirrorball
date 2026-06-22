import Foundation

/// Accessibility identifiers shared by the app and its UI tests as one source of
/// truth. This file is compiled into BOTH the app target and the XCUITest target
/// (XCUITest runs out-of-process and can't see the app's internal symbols), so it
/// stays dependency-free — pure Foundation, no SwiftUI.
enum A11y {
    static let addButton = "mb.addButton"
    static let forwardList = "mb.forwardList"
    static let emptyState = "mb.emptyState"
    static let menuBarOpen = "mb.menuBar.open"

    static func row(_ id: String) -> String { "mb.row.\(id)" }
    static func toggle(_ id: String) -> String { "mb.toggle.\(id)" }
    static func statusDot(_ id: String) -> String { "mb.status.\(id)" }

    enum Editor {
        static let name = "mb.editor.name"
        static let kind = "mb.editor.kind"
        static let target = "mb.editor.target"

        // Port mappings are a dynamic list, so their identifiers are indexed by
        // row. One connection can carry many `-L`/`-R`/`-D` specs.
        static let addPort = "mb.editor.addPort"
        static func portLabel(_ i: Int) -> String { "mb.editor.port.\(i).label" }
        static func listenPort(_ i: Int) -> String { "mb.editor.port.\(i).listen" }
        static func remoteHost(_ i: Int) -> String { "mb.editor.port.\(i).host" }
        static func remotePort(_ i: Int) -> String { "mb.editor.port.\(i).dest" }
        static func removePort(_ i: Int) -> String { "mb.editor.port.\(i).remove" }

        static let save = "mb.editor.save"
        static let cancel = "mb.editor.cancel"
        static let error = "mb.editor.error"
        static let authMethod = "mb.editor.authMethod"
        static let identityFile = "mb.editor.identityFile"
        static let chooseKey = "mb.editor.chooseKey"
        static let secret = "mb.editor.secret"
        static let removeSecret = "mb.editor.removeSecret"
        static let sshPort = "mb.editor.sshPort"
        static let jumpHost = "mb.editor.jumpHost"
        static let extraOptions = "mb.editor.extraOptions"
    }
}
