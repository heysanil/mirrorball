import Foundation

/// Environment-driven configuration. The single place the app reads launch
/// overrides, which is what makes the supervisor and full app deterministically
/// testable from XCUITest and integration tests.
///
/// Recognized environment variables:
/// - `MIRRORBALL_SSH_PATH` — substitute a fake-ssh script for `/usr/bin/ssh`.
/// - `MIRRORBALL_CONFIG_DIR` — redirect persistence to a temp directory.
/// - `MIRRORBALL_DISABLE_SIDE_EFFECTS` — `1` to skip notifications + login item
///   registration (so tests never touch the real user environment).
/// - `MIRRORBALL_SEED` — JSON array of forwards to seed on first launch (tests).
struct AppConfiguration: Sendable {
    var sshExecutableURL: URL
    var configDirectory: URL
    var disableSideEffects: Bool
    var seedJSON: String?

    static let defaultSSHPath = "/usr/bin/ssh"
    static let configDirectoryName = "MirrorballSwift"

    static func fromEnvironment(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppConfiguration {
        let ssh = env["MIRRORBALL_SSH_PATH"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: defaultSSHPath)

        let configDir: URL
        if let override = env["MIRRORBALL_CONFIG_DIR"], !override.isEmpty {
            configDir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            configDir = Self.defaultConfigDirectory
        }

        return AppConfiguration(
            sshExecutableURL: ssh,
            configDirectory: configDir,
            disableSideEffects: env["MIRRORBALL_DISABLE_SIDE_EFFECTS"] == "1",
            seedJSON: env["MIRRORBALL_SEED"]
        )
    }

    /// Location of the askpass helper script ssh uses to fetch a secret.
    var askpassScriptURL: URL {
        configDirectory.appendingPathComponent("askpass.sh", isDirectory: false)
    }

    /// `~/Library/Application Support/MirrorballSwift/`.
    static var defaultConfigDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent(configDirectoryName, isDirectory: true)
    }
}
