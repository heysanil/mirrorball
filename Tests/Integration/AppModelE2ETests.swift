import Foundation
import Testing
@testable import Mirrorball

/// End-to-end coverage through the real `AppModel` — the same state container,
/// supervisor, and persistence the UI drives — using the fake-ssh harness. This
/// runs headlessly (no UI-automation permission needed), complementing the
/// XCUITest flows which cover the view layer.
@Suite("AppModel end-to-end", .timeLimit(.minutes(1)))
@MainActor
struct AppModelE2ETests {
    private func makeConfig(seed: String? = nil, sshBody: String = "exec sleep 100000") throws -> AppConfiguration {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("mb-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let ssh = base.appendingPathComponent("ssh")
        try "#!/bin/bash\n\(sshBody)\n".write(to: ssh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ssh.path)
        return AppConfiguration(
            sshExecutableURL: ssh,
            configDirectory: base.appendingPathComponent("config", isDirectory: true),
            disableSideEffects: true,
            disableUpdater: true,
            seedJSON: seed
        )
    }

    private func pollMain(timeout: Duration, _ predicate: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return predicate()
    }

    @Test("Adding an enabled forward brings it up; toggling off returns it to off")
    func addEnabledThenToggleOff() async throws {
        let model = AppModel(configuration: try makeConfig())
        let entry = model.add(Forward(name: "DB", kind: .local, target: "prod", listenPort: 5432, remoteHost: "db", remotePort: 5432, enabled: true))

        #expect(await pollMain(timeout: .seconds(5)) { entry.status == .up })

        model.toggle(entry) // now disabled
        #expect(await pollMain(timeout: .seconds(3)) { entry.status == .off })
        #expect(entry.forward.enabled == false)
    }

    @Test("A disabled forward stays off and spawns nothing")
    func disabledStaysOff() async throws {
        let model = AppModel(configuration: try makeConfig())
        let entry = model.add(Forward(name: "Idle", kind: .local, target: "prod", listenPort: 1, remotePort: 1, enabled: false))
        // Give it a moment; it must never leave .off.
        _ = await pollMain(timeout: .milliseconds(600)) { false }
        #expect(entry.status == .off)
        #expect(!entry.isSupervised)
    }

    @Test("Changes persist across a reload")
    func persistsAcrossReload() async throws {
        let config = try makeConfig()

        let first = AppModel(configuration: config)
        first.add(Forward(name: "Persisted", kind: .dynamic, target: "bastion", listenPort: 1080, enabled: false))
        #expect(first.entries.count == 1)

        let second = AppModel(configuration: config)
        #expect(second.entries.count == 1)
        #expect(second.entries.first?.forward.name == "Persisted")
        #expect(second.entries.first?.forward.kind == .dynamic)
    }

    @Test("Seeded forwards auto-start on launch")
    func seedAutoStarts() async throws {
        let seed = """
        [{"id":"\(UUID().uuidString)","name":"Seeded","kind":"local","target":"prod","listenPort":7000,"remoteHost":"localhost","remotePort":7000,"enabled":true}]
        """
        let model = AppModel(configuration: try makeConfig(seed: seed))
        model.startEnabledForwards()
        #expect(await pollMain(timeout: .seconds(5)) { model.anyUp })

        // Clean up the child.
        if let entry = model.entries.first { model.toggle(entry) }
        _ = await pollMain(timeout: .seconds(3)) { !model.anyActive }
    }

    @Test("Editing a forward updates it and preserves identity")
    func editPreservesIdentity() async throws {
        let model = AppModel(configuration: try makeConfig())
        let entry = model.add(Forward(name: "Before", kind: .local, target: "prod", listenPort: 1, remotePort: 1, enabled: false))
        let originalID = entry.id

        model.update(entry, with: Forward(name: "After", kind: .remote, target: "edge", listenPort: 2, remotePort: 2, enabled: false))

        #expect(model.entries.count == 1)
        #expect(entry.id == originalID)
        #expect(entry.forward.name == "After")
        #expect(entry.forward.kind == .remote)
    }

    @Test("Deleting a forward removes it and persists the removal")
    func deletePersists() async throws {
        let config = try makeConfig()
        let model = AppModel(configuration: config)
        let entry = model.add(Forward(name: "Doomed", kind: .local, target: "prod", listenPort: 1, remotePort: 1, enabled: false))
        model.delete(entry)
        #expect(model.entries.isEmpty)

        let reloaded = AppModel(configuration: config)
        #expect(reloaded.entries.isEmpty)
    }

    @Test("A multi-mapping forward starts one ssh carrying every spec and comes up")
    func multiMappingForwardComesUpThroughAppModel() async throws {
        // Drive the full AppModel path (add → supervise → spawn) and capture the
        // argv the supervisor actually handed ssh, proving one process multiplexes
        // every mapping rather than one process per port.
        let recording = try makeRecordingFakeSSH()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("mb-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let config = AppConfiguration(
            sshExecutableURL: recording.url,
            configDirectory: base.appendingPathComponent("config", isDirectory: true),
            disableSideEffects: true,
            disableUpdater: true,
            seedJSON: nil
        )
        let model = AppModel(configuration: config)

        let entry = model.add(Forward(
            name: "Devbox",
            kind: .local,
            target: "devbox",
            mappings: [
                PortMapping(label: "frontend", listenPort: 3000, remoteHost: "localhost", remotePort: 3000),
                PortMapping(label: "backend", listenPort: 8080, remoteHost: "localhost", remotePort: 8080),
                PortMapping(label: "db", listenPort: 5432, remoteHost: "localhost", remotePort: 5432),
            ],
            enabled: true
        ))

        #expect(await pollMain(timeout: .seconds(5)) { entry.status == .up })
        #expect(await pollMain(timeout: .seconds(2)) { !recording.invocations.isEmpty })

        // A single supervised ssh carries all three -L specs, in order, target last.
        let invocations = recording.invocations
        #expect(invocations.count == 1)
        let argv = invocations.first ?? []
        #expect(localForwardSpecs(in: argv) == [
            "3000:localhost:3000",
            "8080:localhost:8080",
            "5432:localhost:5432",
        ])
        #expect(argv.last == "devbox")

        // Tear the child down cleanly.
        model.toggle(entry)
        _ = await pollMain(timeout: .seconds(3)) { entry.status == .off }
    }

    @Test("A password forward authenticates via askpass and clears its secret on delete")
    func passwordForwardAuthenticatesAndClearsSecret() async throws {
        let store = InMemorySecretStore()
        // Fake ssh only stays up if it fetches the right secret through askpass.
        let config = try makeConfig(
            sshBody: #"s=$("$SSH_ASKPASS" "Password:"); if [ "$s" = "swordfish" ]; then exec sleep 100000; else echo "auth failed" >&2; exit 1; fi"#
        )
        let model = AppModel(configuration: config, secretStore: store)

        let entry = model.add(
            Forward(name: "Pwd", kind: .local, target: "prod", listenPort: 5432, remoteHost: "db", remotePort: 5432, enabled: true, authMethod: .password),
            secret: .set("swordfish")
        )
        #expect(store.hasSecret(for: entry.id))
        #expect(await pollMain(timeout: .seconds(5)) { entry.status == .up })

        model.toggle(entry) // stop the tunnel before deleting
        _ = await pollMain(timeout: .seconds(3)) { entry.status == .off }
        model.delete(entry)
        #expect(!store.hasSecret(for: entry.id))
    }
}
