import Foundation
import Testing
@testable import Mirrorball

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

    @Test("A connection that passes grace then fails surfaces the error reason, not a silent reconnect")
    func unstableDropSurfacesReason() async throws {
        // Survives the 1.5s grace (so it's marked .up), then exits non-zero with a
        // stderr line — a flapping/failing connection, not a clean transient drop.
        let ssh = try makeFakeSSH(body: #"sleep 1.8; echo "Connection reset by peer" >&2; exit 255"#)
        let sup = TunnelSupervisor(forward: sampleForward(), sshExecutableURL: ssh)
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()
        #expect(await poll(timeout: .seconds(4)) { collector.sawUp })
        // The real reason must be surfaced rather than a contextless "reconnecting".
        #expect(await poll(timeout: .seconds(4)) {
            collector.lastError?.contains("Connection reset by peer") == true
        })

        await sup.stop()
        #expect(await poll(timeout: .seconds(3)) { collector.isOff })
    }

    @Test("A clean drop (exit 0, no stderr) stays a quiet reconnect")
    func cleanDropStaysReconnect() async throws {
        let ssh = try makeFakeSSH(body: "sleep 1.8; exit 0")
        let sup = TunnelSupervisor(forward: sampleForward(), sshExecutableURL: ssh)
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()
        #expect(await poll(timeout: .seconds(5)) { collector.sawUp })
        #expect(await poll(timeout: .seconds(5)) { collector.sawReconnecting })
        // No spurious error for a clean close.
        #expect(collector.lastError == nil)

        await sup.stop()
        #expect(await poll(timeout: .seconds(3)) { collector.isOff })
    }

    @Test("A stable connection that later drops with a reason reconnects quietly, not as a failure")
    func stableDropDoesNotSurfaceAsError() async throws {
        // The user's bug: a tunnel that was solidly up for a while, then gets
        // killed by a NAT/idle timeout (ssh exits 255 with a stderr line), must
        // be treated as a transient reconnect — NOT a "Forward failed" error that
        // immediately recovers. Inject a tiny stability window so the fake ssh
        // only has to stay up briefly past the grace window to count as "stable".
        let ssh = try makeFakeSSH(
            body: #"sleep 2.5; echo "client_loop: send disconnect: Broken pipe" >&2; exit 255"#
        )
        let sup = TunnelSupervisor(
            forward: sampleForward(),
            sshExecutableURL: ssh,
            stableAfter: .milliseconds(200)
        )
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()
        #expect(await poll(timeout: .seconds(4)) { collector.sawUp })
        // A previously-stable drop is a reconnect…
        #expect(await poll(timeout: .seconds(5)) { collector.sawReconnecting })
        // …and must never masquerade as an error (which would fire "Forward failed").
        #expect(collector.lastError == nil)

        await sup.stop()
        #expect(await poll(timeout: .seconds(3)) { collector.isOff })
    }

    @Test("A multi-mapping forward spawns one ssh carrying every -L spec in order")
    func multiMappingSpawnsOneSSHWithAllSpecs() async throws {
        // Three mappings over one connection (frontend + backend + db on a devbox).
        let recording = try makeRecordingFakeSSH()
        let forward = sampleForward(mappings: [
            PortMapping(label: "frontend", listenPort: 3000, remoteHost: "localhost", remotePort: 3000),
            PortMapping(label: "backend", listenPort: 8080, remoteHost: "localhost", remotePort: 8080),
            PortMapping(label: "db", listenPort: 5432, remoteHost: "localhost", remotePort: 5432),
        ])
        let sup = TunnelSupervisor(forward: forward, sshExecutableURL: recording.url)
        let collector = collectStatuses(from: sup.statusStream)

        await sup.start()
        // Survives the grace window → exactly one healthy ssh process.
        #expect(await poll(timeout: .seconds(5)) { collector.sawUp })
        #expect(await poll(timeout: .seconds(2)) { !recording.invocations.isEmpty })

        // One ssh invocation multiplexes all three forwards (no extra spawns).
        let invocations = recording.invocations
        #expect(invocations.count == 1)

        // It carries one -L spec per mapping, in list order, with the target last.
        let argv = invocations.first ?? []
        #expect(localForwardSpecs(in: argv) == [
            "3000:localhost:3000",
            "8080:localhost:8080",
            "5432:localhost:5432",
        ])
        #expect(argv.last == "host")

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
