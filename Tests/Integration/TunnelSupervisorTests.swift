import Foundation
import Testing
@testable import MirrorballSwift

@Suite("TunnelSupervisor", .timeLimit(.minutes(1)))
struct TunnelSupervisorTests {
    @Test("A healthy connection reaches .up, then stop() returns it to .off")
    func healthyThenStop() async throws {
        let ssh = try makeFakeSSH(body: FakeSSH.staysUp)
        let sup = TunnelSupervisor(forward: sampleForward(), sshExecutableURL: ssh)
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()
        #expect(await poll(timeout: .seconds(5)) { collector.sawUp })

        await sup.stop()
        #expect(await poll(timeout: .seconds(3)) { collector.isOff })

        // A healthy tunnel must never have looked like an unexpected drop.
        #expect(!collector.sawReconnecting)
    }

    @Test("An immediate failure surfaces the stderr line and retries with backoff")
    func immediateFailureRetries() async throws {
        let ssh = try makeFakeSSH(body: FakeSSH.failsImmediately)
        let sup = TunnelSupervisor(forward: sampleForward(), sshExecutableURL: ssh)
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()

        // The last stderr line is surfaced as the error message.
        #expect(await poll(timeout: .seconds(4)) {
            collector.lastError?.contains("Address already in use") == true
        })
        // Backoff retries: a second spawn attempt happens (~1s backoff).
        #expect(await poll(timeout: .seconds(4)) { collector.startingCount >= 2 })

        await sup.stop()
        #expect(await poll(timeout: .seconds(3)) { collector.isOff })
    }

    @Test("An unexpected drop after coming up transitions to .reconnecting")
    func dropTransitionsToReconnecting() async throws {
        let ssh = try makeFakeSSH(body: FakeSSH.dropsAfterComingUp)
        let sup = TunnelSupervisor(forward: sampleForward(), sshExecutableURL: ssh)
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()
        #expect(await poll(timeout: .seconds(5)) { collector.sawUp })
        #expect(await poll(timeout: .seconds(6)) { collector.sawReconnecting })

        await sup.stop()
        #expect(await poll(timeout: .seconds(3)) { collector.isOff })
    }

    @Test("A bad ssh path reports an error instead of crashing")
    func badExecutablePath() async throws {
        let missing = URL(fileURLWithPath: "/nonexistent/ssh-binary")
        let sup = TunnelSupervisor(forward: sampleForward(), sshExecutableURL: missing)
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()
        #expect(await poll(timeout: .seconds(4)) { collector.lastError != nil })

        await sup.stop()
        #expect(await poll(timeout: .seconds(3)) { collector.isOff })
    }

    @Test("Status stream emits no duplicate consecutive states")
    func dedupesConsecutiveStates() async throws {
        let ssh = try makeFakeSSH(body: FakeSSH.staysUp)
        let sup = TunnelSupervisor(forward: sampleForward(), sshExecutableURL: ssh)
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()
        #expect(await poll(timeout: .seconds(5)) { collector.sawUp })
        await sup.stop()
        #expect(await poll(timeout: .seconds(3)) { collector.isOff })

        let states = collector.snapshot
        for (a, b) in zip(states, states.dropFirst()) {
            #expect(a != b, "found duplicate consecutive status \(a)")
        }
    }
}
