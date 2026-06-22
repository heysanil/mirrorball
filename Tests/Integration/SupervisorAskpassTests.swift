import Foundation
import Testing
@testable import Mirrorball

/// Proves the secret-injection path end-to-end: a fake `ssh` that actually execs
/// `$SSH_ASKPASS` to fetch the secret, and only connects when it matches. No real
/// SSH, no Keychain — just the env hand-off the supervisor performs.
@Suite("Supervisor askpass injection", .timeLimit(.minutes(1)))
struct SupervisorAskpassTests {
    /// Write an executable askpass script that echoes the env-provided secret —
    /// the same contract as the app's AskpassHelper, created here so this slice
    /// stays self-contained.
    private func makeAskpass() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mb-askpass-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("askpass.sh", isDirectory: false)
        try "#!/bin/sh\nprintf '%s\\n' \"$MIRRORBALL_ASKPASS_SECRET\"\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test("Correct secret reaches the tunnel via askpass and it comes up")
    func correctSecretConnects() async throws {
        let askpass = try makeAskpass()
        // Fake ssh fetches the secret through askpass and only stays up if it matches.
        let ssh = try makeFakeSSH(body: #"s=$("$SSH_ASKPASS" "Password:"); if [ "$s" = "swordfish" ]; then exec sleep 100000; else echo "auth failed: bad secret" >&2; exit 1; fi"#)
        let sup = TunnelSupervisor(forward: sampleForward(), sshExecutableURL: ssh, secret: "swordfish", askpassURL: askpass)
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()
        #expect(await poll(timeout: .seconds(5)) { collector.sawUp })

        await sup.stop()
        #expect(await poll(timeout: .seconds(3)) { collector.isOff })
    }

    @Test("Wrong secret surfaces the auth error")
    func wrongSecretFails() async throws {
        let askpass = try makeAskpass()
        let ssh = try makeFakeSSH(body: #"s=$("$SSH_ASKPASS" "Password:"); if [ "$s" = "swordfish" ]; then exec sleep 100000; else echo "auth failed: bad secret" >&2; exit 1; fi"#)
        let sup = TunnelSupervisor(forward: sampleForward(), sshExecutableURL: ssh, secret: "wrong", askpassURL: askpass)
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()
        #expect(await poll(timeout: .seconds(4)) {
            collector.lastError?.contains("auth failed") == true
        })
        #expect(!collector.sawUp)

        await sup.stop()
        #expect(await poll(timeout: .seconds(3)) { collector.isOff })
    }

    @Test("No secret means SSH_ASKPASS is never set")
    func noSecretLeavesAskpassUnset() async throws {
        // Fake ssh insists SSH_ASKPASS is empty; supervisor passes no secret/askpass.
        let ssh = try makeFakeSSH(body: #"if [ -z "$SSH_ASKPASS" ]; then exec sleep 100000; else echo "unexpected askpass" >&2; exit 1; fi"#)
        let sup = TunnelSupervisor(forward: sampleForward(), sshExecutableURL: ssh)
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()
        #expect(await poll(timeout: .seconds(5)) { collector.sawUp })

        await sup.stop()
        #expect(await poll(timeout: .seconds(3)) { collector.isOff })
    }
}
