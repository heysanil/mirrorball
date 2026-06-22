import Testing
@testable import Mirrorball

@Suite("Draft validation")
struct DraftForwardTests {
    private func validLocal() -> DraftForward {
        var d = DraftForward()
        d.name = "Prod DB"
        d.kind = .local
        d.target = "prod"
        d.mappings = [DraftPortMapping(listenPort: "5432", remoteHost: "db", remotePort: "5432")]
        return d
    }

    @Test("A complete local draft validates into a Forward")
    func validLocalDraft() throws {
        let result = validLocal().validate()
        let forward = try result.get()
        #expect(forward.name == "Prod DB")
        #expect(forward.kind == .local)
        #expect(forward.mappings.count == 1)
        #expect(forward.mappings[0].listenPort == 5432)
        #expect(forward.mappings[0].remoteHost == "db")
        #expect(forward.mappings[0].remotePort == 5432)
    }

    @Test("Empty name is rejected")
    func rejectsEmptyName() {
        var d = validLocal(); d.name = "   "
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("Empty target is rejected")
    func rejectsEmptyTarget() {
        var d = validLocal(); d.target = ""
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("An empty mappings list is rejected")
    func rejectsEmptyMappings() {
        var d = validLocal(); d.mappings = []
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("Non-numeric or out-of-range listen port is rejected")
    func rejectsBadListenPort() {
        var d = validLocal(); d.mappings[0].listenPort = "0"
        #expect(throws: ValidationError.self) { try d.validate().get() }
        d.mappings[0].listenPort = "70000"
        #expect(throws: ValidationError.self) { try d.validate().get() }
        d.mappings[0].listenPort = "abc"
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("A non-numeric destination port is rejected")
    func rejectsBadDestinationPort() {
        var d = validLocal(); d.mappings[0].remotePort = "abc"
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("A blank destination port defaults to the listen port")
    func blankDestinationPortDefaultsToListen() throws {
        var d = validLocal(); d.mappings[0].remotePort = ""
        let forward = try d.validate().get()
        #expect(forward.mappings[0].remotePort == 5432)  // mirrors the listen port
    }

    @Test("Dynamic ignores destination fields and defaults them")
    func dynamicIgnoresDestination() throws {
        var d = DraftForward()
        d.name = "SOCKS"; d.kind = .dynamic; d.target = "bastion"
        d.mappings = [DraftPortMapping(listenPort: "1080", remotePort: "")]
        let forward = try d.validate().get()
        #expect(forward.kind == .dynamic)
        #expect(forward.mappings[0].listenPort == 1080)
        #expect(forward.mappings[0].remoteHost == "localhost")
        #expect(forward.mappings[0].remotePort == 0)
    }

    @Test("Blank destination host defaults to localhost")
    func blankRemoteHostDefaults() throws {
        var d = validLocal(); d.mappings[0].remoteHost = "  "
        let forward = try d.validate().get()
        #expect(forward.mappings[0].remoteHost == "localhost")
    }

    @Test("A multi-mapping draft validates into ordered mappings with labels")
    func multiMappingDraft() throws {
        var d = DraftForward()
        d.name = "Devbox"; d.kind = .local; d.target = "devbox"
        d.mappings = [
            DraftPortMapping(label: "frontend", listenPort: "3000", remoteHost: "localhost", remotePort: "3000"),
            DraftPortMapping(label: "backend", listenPort: "8080", remoteHost: "localhost", remotePort: ""),
            DraftPortMapping(label: "", listenPort: "5432", remoteHost: "db.internal", remotePort: "5432"),
        ]
        let forward = try d.validate().get()
        #expect(forward.mappings.count == 3)
        #expect(forward.mappings.map(\.listenPort) == [3000, 8080, 5432])
        #expect(forward.mappings.map(\.label) == ["frontend", "backend", ""])
        // Smart default: backend's blank dest port mirrors its listen port.
        #expect(forward.mappings[1].remotePort == 8080)
        #expect(forward.mappings[2].remoteHost == "db.internal")
    }

    @Test("A mapping label is trimmed but may be empty")
    func labelTrimmed() throws {
        var d = validLocal(); d.mappings[0].label = "  api  "
        let forward = try d.validate().get()
        #expect(forward.mappings[0].label == "api")
    }

    @Test("Duplicate listen ports within one forward are rejected")
    func rejectsDuplicateListenPorts() {
        var d = DraftForward()
        d.name = "Dupe"; d.kind = .local; d.target = "h"
        d.mappings = [
            DraftPortMapping(listenPort: "3000", remotePort: "3000"),
            DraftPortMapping(listenPort: "3000", remotePort: "9000"),
        ]
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("Duplicate listen ports produce a friendly message naming the port")
    func duplicateListenPortMessage() {
        var d = DraftForward()
        d.name = "Dupe"; d.kind = .local; d.target = "h"
        d.mappings = [
            DraftPortMapping(listenPort: "3000", remotePort: "3000"),
            DraftPortMapping(listenPort: "3000", remotePort: "9000"),
        ]
        switch d.validate() {
        case .success: Issue.record("expected the duplicate port to be rejected")
        case .failure(let error): #expect(error.message == "Port 3000 is forwarded more than once.")
        }
    }

    @Test("Round-trips an existing forward through the draft")
    func roundTripExisting() throws {
        let original = Forward(name: "API", kind: .remote, target: "edge", listenPort: 9000, remoteHost: "127.0.0.1", remotePort: 3000, enabled: true)
        let rebuilt = try DraftForward(original).validate().get()
        #expect(rebuilt.kind == .remote)
        #expect(rebuilt.mappings[0].listenPort == 9000)
        #expect(rebuilt.mappings[0].remoteHost == "127.0.0.1")
        #expect(rebuilt.mappings[0].remotePort == 3000)
    }

    @Test("Listen-port label changes with kind")
    func listenPortLabel() {
        var d = DraftForward(); d.kind = .local
        #expect(d.listenPortLabel == "Local port")
        d.kind = .remote
        #expect(d.listenPortLabel == "Remote bind port")
    }
}
