import Foundation
import Testing
@testable import Mirrorball

@Suite("Forward model")
struct ForwardModelTests {
    @Test("ForwardKind badges and endpoint usage are correct")
    func kindMetadata() {
        #expect(ForwardKind.local.badge == "LOCAL")
        #expect(ForwardKind.remote.badge == "REMOTE")
        #expect(ForwardKind.dynamic.badge == "SOCKS")
        #expect(ForwardKind.local.usesRemoteEndpoint)
        #expect(ForwardKind.remote.usesRemoteEndpoint)
        #expect(!ForwardKind.dynamic.usesRemoteEndpoint)
        #expect(ForwardKind.allCases.count == 3)
    }

    @Test("Effective remote host falls back to localhost")
    func effectiveRemoteHost() {
        #expect(Forward(name: "a", kind: .local, target: "h", listenPort: 1, remoteHost: "").effectiveRemoteHost == "localhost")
        #expect(Forward(name: "a", kind: .local, target: "h", listenPort: 1, remoteHost: "db").effectiveRemoteHost == "db")
    }

    @Test("Codable round-trips with id preserved")
    func codableRoundTrip() throws {
        let original = Forward(
            name: "Prod database",
            kind: .local,
            target: "prod",
            listenPort: 5432,
            remoteHost: "db",
            remotePort: 5432,
            enabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Forward.self, from: data)
        #expect(decoded == original)
        #expect(decoded.id == original.id)
    }

    @Test("Decoding tolerates a record missing optional fields")
    func tolerantDecoding() throws {
        // No id / remoteHost / remotePort / enabled present.
        let json = """
        { "name": "x", "kind": "dynamic", "target": "bastion", "listenPort": 1080 }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Forward.self, from: json)
        #expect(decoded.name == "x")
        #expect(decoded.kind == .dynamic)
        #expect(decoded.remoteHost == "localhost")
        #expect(decoded.remotePort == 0)
        #expect(decoded.enabled == false)
    }

    @Test("Backoff doubles and caps at the max")
    func backoffDoubling() {
        let one = Duration.seconds(1)
        let max = Duration.seconds(30)
        #expect(one.doubled(upTo: max) == .seconds(2))
        #expect(Duration.seconds(16).doubled(upTo: max) == .seconds(30))
        #expect(Duration.seconds(30).doubled(upTo: max) == .seconds(30))
    }
}
