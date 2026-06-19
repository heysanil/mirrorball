import Foundation

/// Installs the tiny askpass script that hands a secret to `ssh` without ever
/// putting it on the command line.
///
/// When a forward needs a password or key passphrase, `ssh` is launched with
/// `SSH_ASKPASS` pointing at this script and `SSH_ASKPASS_REQUIRE=force`. `ssh`
/// then *executes the script* to obtain the secret instead of reading a TTY. The
/// script simply echoes `MIRRORBALL_ASKPASS_SECRET`, which the supervisor places
/// in the ssh child's environment only — so the secret travels via inherited env,
/// never via argv where it would be visible in `ps`.
enum AskpassHelper {
    /// The exact script body. `printf '%s\n'` avoids `echo`'s flag/escape quirks
    /// and emits the secret followed by a single newline, which is what `ssh`
    /// expects from an askpass program.
    private static let scriptBody = "#!/bin/sh\nprintf '%s\\n' \"$MIRRORBALL_ASKPASS_SECRET\"\n"

    /// Write the askpass script to `url`, marking it owner-executable (0o755) and
    /// creating the parent directory if needed. Idempotent: an existing script is
    /// overwritten, so re-installing on every launch is safe.
    static func install(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try scriptBody.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
