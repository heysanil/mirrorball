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
        static let listenPort = "mb.editor.listenPort"
        static let remoteHost = "mb.editor.remoteHost"
        static let remotePort = "mb.editor.remotePort"
        static let save = "mb.editor.save"
        static let cancel = "mb.editor.cancel"
        static let error = "mb.editor.error"
    }
}
