import Testing
@testable import MirrorballSwift

@Suite("Draft validation")
struct DraftForwardTests {
    private func validLocal() -> DraftForward {
        var d = DraftForward()
        d.name = "Prod DB"
        d.kind = .local
        d.target = "prod"
        d.listenPort = "5432"
        d.remoteHost = "db"
        d.remotePort = "5432"
        return d
    }

    @Test("A complete local draft validates into a Forward")
    func validLocalDraft() throws {
        let result = validLocal().validate()
        let forward = try result.get()
        #expect(forward.name == "Prod DB")
        #expect(forward.kind == .local)
        #expect(forward.listenPort == 5432)
        #expect(forward.remoteHost == "db")
        #expect(forward.remotePort == 5432)
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

    @Test("Non-numeric or out-of-range listen port is rejected")
    func rejectsBadListenPort() {
        var d = validLocal(); d.listenPort = "0"
        #expect(throws: ValidationError.self) { try d.validate().get() }
        d.listenPort = "70000"
        #expect(throws: ValidationError.self) { try d.validate().get() }
        d.listenPort = "abc"
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("Local/Remote require a valid destination port")
    func remoteEndpointRequiresPort() {
        var d = validLocal(); d.remotePort = ""
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("Dynamic ignores destination fields and defaults them")
    func dynamicIgnoresDestination() throws {
        var d = DraftForward()
        d.name = "SOCKS"; d.kind = .dynamic; d.target = "bastion"; d.listenPort = "1080"
        d.remotePort = ""  // not required for dynamic
        let forward = try d.validate().get()
        #expect(forward.kind == .dynamic)
        #expect(forward.listenPort == 1080)
        #expect(forward.remoteHost == "localhost")
        #expect(forward.remotePort == 0)
    }

    @Test("Blank destination host defaults to localhost")
    func blankRemoteHostDefaults() throws {
        var d = validLocal(); d.remoteHost = "  "
        let forward = try d.validate().get()
        #expect(forward.remoteHost == "localhost")
    }

    @Test("Round-trips an existing forward through the draft")
    func roundTripExisting() throws {
        let original = Forward(name: "API", kind: .remote, target: "edge", listenPort: 9000, remoteHost: "127.0.0.1", remotePort: 3000, enabled: true)
        let rebuilt = try DraftForward(original).validate().get()
        #expect(rebuilt.kind == .remote)
        #expect(rebuilt.listenPort == 9000)
        #expect(rebuilt.remoteHost == "127.0.0.1")
        #expect(rebuilt.remotePort == 3000)
    }

    @Test("Listen-port label changes with kind")
    func listenPortLabel() {
        var d = DraftForward(); d.kind = .local
        #expect(d.listenPortLabel == "Local port")
        d.kind = .remote
        #expect(d.listenPortLabel == "Remote bind port")
    }
}
