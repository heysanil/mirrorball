import Foundation
import Testing
@testable import MirrorballSwift

@Suite("Persistence")
struct PersistenceTests {
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
