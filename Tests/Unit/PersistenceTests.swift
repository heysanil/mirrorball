import Foundation
import Testing
@testable import Mirrorball

@Suite("Persistence")
struct PersistenceTests {
    private func backupFiles(in dir: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("forwards.corrupt-") }
    }

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirrorball-tests-\(UUID().uuidString)", isDirectory: true)
        return dir
    }

    @Test("Saving then loading round-trips the forwards")
    func roundTrip() throws {
        let store = Persistence(configDirectory: tempDir())
        let forwards = [
            Forward(name: "Prod DB", kind: .local, target: "prod", listenPort: 5432, remoteHost: "db", remotePort: 5432, enabled: true),
            Forward(name: "SOCKS", kind: .dynamic, target: "bastion", listenPort: 1080),
        ]
        try store.save(forwards)
        #expect(store.load() == forwards)
    }

    @Test("Loading a missing file returns an empty list")
    func missingFile() {
        let store = Persistence(configDirectory: tempDir())
        #expect(store.load().isEmpty)
    }

    @Test("Loading a malformed file degrades to empty rather than throwing")
    func malformedFile() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Persistence(configDirectory: dir)
        try "not json {{{".data(using: .utf8)!.write(to: store.fileURL)
        #expect(store.load().isEmpty)
    }

    @Test("A malformed file is backed up before degrading to empty")
    func malformedFileIsBackedUp() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Persistence(configDirectory: dir)
        let original = Data("not json {{{".utf8)
        try original.write(to: store.fileURL)

        #expect(store.load().isEmpty)
        let backups = try backupFiles(in: dir)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: try #require(backups.first)) == original)
    }

    @Test("One undecodable forward is skipped, the rest load, and the file is backed up")
    func partiallyInvalidFile() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Persistence(configDirectory: dir)
        let good = Forward(name: "Good", kind: .local, target: "a", listenPort: 1, remotePort: 1)
        try store.save([good])

        // Splice an entry with an unknown `kind` (e.g. written by a newer version)
        // in front of the valid one.
        var array = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [Any]
        )
        var bad = try #require(array.first as? [String: Any])
        bad["kind"] = "teleport"
        array.insert(bad, at: 0)
        let original = try JSONSerialization.data(withJSONObject: array)
        try original.write(to: store.fileURL)

        #expect(store.load() == [good])
        let backups = try backupFiles(in: dir)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: try #require(backups.first)) == original)
    }

    @Test("A clean load or a missing file creates no backup")
    func noBackupWhenNothingWasLost() throws {
        let dir = tempDir()
        let store = Persistence(configDirectory: dir)
        _ = store.load()
        try store.save([Forward(name: "ok", kind: .dynamic, target: "b", listenPort: 1080)])
        _ = store.load()
        #expect(try backupFiles(in: dir).isEmpty)
    }

    @Test("Save overwrites previous contents")
    func overwrite() throws {
        let store = Persistence(configDirectory: tempDir())
        try store.save([Forward(name: "one", kind: .local, target: "a", listenPort: 1, remotePort: 1)])
        try store.save([Forward(name: "two", kind: .remote, target: "b", listenPort: 2, remotePort: 2)])
        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "two")
    }
}
