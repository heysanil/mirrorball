import Foundation
import Testing
@testable import Mirrorball

@Suite("Secret storage")
struct SecretStoreTests {
    // MARK: InMemorySecretStore

    @Test("set then get round-trips a secret")
    func setThenGet() {
        let store = InMemorySecretStore()
        let id = UUID()
        store.apply(.set("hunter2"), for: id)
        #expect(store.secret(for: id) == "hunter2")
    }

    @Test("hasSecret reflects presence")
    func hasSecretPresence() {
        let store = InMemorySecretStore()
        let id = UUID()
        #expect(store.hasSecret(for: id) == false)
        store.apply(.set("x"), for: id)
        #expect(store.hasSecret(for: id) == true)
    }

    @Test(".set overwrites an existing secret")
    func overwrite() {
        let store = InMemorySecretStore()
        let id = UUID()
        store.apply(.set("first"), for: id)
        store.apply(.set("second"), for: id)
        #expect(store.secret(for: id) == "second")
    }

    @Test(".clear deletes the stored secret")
    func clearDeletes() {
        let store = InMemorySecretStore()
        let id = UUID()
        store.apply(.set("gone"), for: id)
        store.apply(.clear, for: id)
        #expect(store.secret(for: id) == nil)
        #expect(store.hasSecret(for: id) == false)
    }

    @Test(".unchanged is a no-op")
    func unchangedIsNoop() {
        let store = InMemorySecretStore()
        let id = UUID()
        store.apply(.set("keep"), for: id)
        store.apply(.unchanged, for: id)
        #expect(store.secret(for: id) == "keep")

        // No-op also leaves an empty slot empty.
        let empty = UUID()
        store.apply(.unchanged, for: empty)
        #expect(store.secret(for: empty) == nil)
    }

    @Test("distinct ids are independent")
    func distinctIdsIndependent() {
        let store = InMemorySecretStore()
        let a = UUID()
        let b = UUID()
        store.apply(.set("a-secret"), for: a)
        store.apply(.set("b-secret"), for: b)
        #expect(store.secret(for: a) == "a-secret")
        #expect(store.secret(for: b) == "b-secret")

        store.apply(.clear, for: a)
        #expect(store.secret(for: a) == nil)
        #expect(store.secret(for: b) == "b-secret")
    }

    // MARK: SecretUpdate equality

    @Test("SecretUpdate equality basics")
    func secretUpdateEquality() {
        #expect(SecretUpdate.unchanged == .unchanged)
        #expect(SecretUpdate.clear == .clear)
        #expect(SecretUpdate.set("a") == .set("a"))
        #expect(SecretUpdate.set("a") != .set("b"))
        #expect(SecretUpdate.unchanged != .clear)
        #expect(SecretUpdate.clear != .set(""))
    }

    // MARK: AskpassHelper (no Keychain involved)

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mirrorball-askpass-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("askpass.sh", isDirectory: false)
    }

    @Test("install writes an executable script that echoes the env secret")
    func installRunsAndEchoesSecret() throws {
        let url = tempURL()
        try AskpassHelper.install(at: url)

        // The script must be owner-executable for ssh to invoke it.
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        #expect(perms & 0o100 != 0)  // owner-execute bit set

        // Run it directly with the secret only in the environment, mirroring how
        // the supervisor hands the secret to the ssh child.
        let process = Process()
        process.executableURL = url
        process.environment = ["MIRRORBALL_ASKPASS_SECRET": "swordfish"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .newlines)
        #expect(output == "swordfish")
        #expect(process.terminationStatus == 0)
    }

    @Test("install is idempotent — overwriting an existing script works")
    func installIsIdempotent() throws {
        let url = tempURL()
        try AskpassHelper.install(at: url)
        try AskpassHelper.install(at: url)  // must not throw on overwrite

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        #expect(perms & 0o100 != 0)
    }
}
