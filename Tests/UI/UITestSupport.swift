import Foundation
import XCTest

/// Per-test sandbox for driving the real app deterministically: a temp config
/// dir and a fake-`ssh` script, injected via launch environment. No real SSH,
/// no real network, no touching the user's notification center or login item.
struct UITestContext {
    let baseDir: URL
    let configDir: URL
    let sshPath: URL
    let seed: String?

    /// `sshBody` defaults to a process that "connects" and stays up until killed.
    init(seed: String? = nil, sshBody: String = "exec sleep 100000") {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("mb-uitest-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        baseDir = base
        configDir = base.appendingPathComponent("config", isDirectory: true)
        sshPath = base.appendingPathComponent("ssh", isDirectory: false)
        try! "#!/bin/bash\n\(sshBody)\n".write(to: sshPath, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sshPath.path)
        self.seed = seed
    }

    func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MIRRORBALL_DISABLE_SIDE_EFFECTS"] = "1"
        app.launchEnvironment["MIRRORBALL_CONFIG_DIR"] = configDir.path
        app.launchEnvironment["MIRRORBALL_SSH_PATH"] = sshPath.path
        if let seed {
            app.launchEnvironment["MIRRORBALL_SEED"] = seed
        }
        return app
    }
}

extension XCUIApplication {
    /// Find an element by accessibility identifier regardless of its resolved type
    /// (SwiftUI shapes/labels resolve to varying XCUIElement types on macOS).
    func element(id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }
}

/// Seeds with stable ids so tests can target rows, toggles, and status dots.
enum Seeds {
    static let disabledLocalID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"

    static let oneDisabledLocal = """
    [{"id":"\(disabledLocalID)","name":"Prod DB","kind":"local","target":"prod","listenPort":5432,"remoteHost":"localhost","remotePort":5432,"enabled":false}]
    """
}
