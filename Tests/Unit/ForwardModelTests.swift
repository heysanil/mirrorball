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
        #expect(PortMapping(listenPort: 1, remoteHost: "").effectiveRemoteHost == "localhost")
        #expect(PortMapping(listenPort: 1, remoteHost: "   ").effectiveRemoteHost == "localhost")
        #expect(PortMapping(listenPort: 1, remoteHost: "db").effectiveRemoteHost == "db")
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

    @Test("A multi-mapping forward round-trips preserving order, labels, and ids")
    func multiMappingRoundTrip() throws {
        let original = Forward(
            name: "Devbox",
            kind: .local,
            target: "devbox",
            mappings: [
                PortMapping(label: "frontend", listenPort: 3000, remoteHost: "localhost", remotePort: 3000),
                PortMapping(label: "backend", listenPort: 8080, remoteHost: "localhost", remotePort: 8080),
                PortMapping(label: "db", listenPort: 5432, remoteHost: "db.internal", remotePort: 5432),
            ],
            enabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Forward.self, from: data)
        #expect(decoded == original)
        #expect(decoded.mappings.map(\.label) == ["frontend", "backend", "db"])
        #expect(decoded.mappings.map(\.id) == original.mappings.map(\.id))
        #expect(decoded.mappings.map(\.listenPort) == [3000, 8080, 5432])
    }

    @Test("Encoded JSON carries mappings and drops the legacy port keys")
    func encodeOmitsLegacyKeys() throws {
        let forward = Forward(name: "x", kind: .local, target: "h", listenPort: 5432, remoteHost: "db", remotePort: 5432)
        let data = try JSONEncoder().encode(forward)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["mappings"] != nil)
        #expect(object["listenPort"] == nil)
        #expect(object["remoteHost"] == nil)
        #expect(object["remotePort"] == nil)
    }

    @Test("Legacy single-port JSON migrates to exactly one mapping")
    func legacySinglePortDecoding() throws {
        let json = """
        {
          "id": "1B9D6BCD-BBFD-4B2D-9B5D-AB8DFBBD4BED",
          "name": "Prod DB", "kind": "local", "target": "prod",
          "listenPort": 5432, "remoteHost": "db", "remotePort": 5432,
          "enabled": true
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Forward.self, from: json)
        #expect(decoded.mappings.count == 1)
        #expect(decoded.mappings[0].listenPort == 5432)
        #expect(decoded.mappings[0].remoteHost == "db")
        #expect(decoded.mappings[0].remotePort == 5432)
        #expect(decoded.mappings[0].label == "")
        #expect(decoded.name == "Prod DB")
    }

    @Test("Decoding tolerates a record missing optional fields")
    func tolerantDecoding() throws {
        // No id / remoteHost / remotePort / enabled / mappings present — the legacy
        // flat shape is migrated into a single mapping with defaulted fields.
        let json = """
        { "name": "x", "kind": "dynamic", "target": "bastion", "listenPort": 1080 }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Forward.self, from: json)
        #expect(decoded.name == "x")
        #expect(decoded.kind == .dynamic)
        #expect(decoded.mappings.count == 1)
        #expect(decoded.mappings[0].listenPort == 1080)
        #expect(decoded.mappings[0].remoteHost == "localhost")
        #expect(decoded.mappings[0].remotePort == 0)
        #expect(decoded.enabled == false)
    }

    @Test("Mapping spec description uses a bare local port and the remote endpoint")
    func mappingSpecDescription() {
        // Local: bind side is a bare port; destination keeps its host (localhost
        // here means "the server itself"), so the two no longer read identically.
        let local = PortMapping(listenPort: 3000, remoteHost: "localhost", remotePort: 3000)
        #expect(local.specDescription(for: .local) == ":3000 → localhost:3000")

        let localNamed = PortMapping(listenPort: 5432, remoteHost: "db.internal", remotePort: 5432)
        #expect(localNamed.specDescription(for: .local) == ":5432 → db.internal:5432")

        // Remote keeps its explicit "server:" bind label.
        let remote = PortMapping(listenPort: 8080, remoteHost: "localhost", remotePort: 3000)
        #expect(remote.specDescription(for: .remote) == "server:8080 → localhost:3000")

        let dynamic = PortMapping(listenPort: 1080)
        #expect(dynamic.specDescription(for: .dynamic) == "SOCKS on :1080")
    }

    @Test("Ports summary prefers labels, falls back to ports, and collapses when long")
    func portsSummary() {
        let labelled = Forward(name: "a", kind: .local, target: "h", mappings: [
            PortMapping(label: "frontend", listenPort: 3000),
            PortMapping(label: "backend", listenPort: 8080),
        ])
        #expect(labelled.portsSummary == "frontend, backend")

        let ports = Forward(name: "a", kind: .local, target: "h", mappings: [
            PortMapping(listenPort: 3000),
            PortMapping(listenPort: 8080),
            PortMapping(listenPort: 5432),
        ])
        #expect(ports.portsSummary == ":3000 :8080 :5432")

        let socks = Forward(name: "a", kind: .dynamic, target: "h", listenPort: 1080)
        #expect(socks.portsSummary == "SOCKS :1080")

        let many = Forward(name: "a", kind: .local, target: "h",
                           mappings: (1...5).map { PortMapping(listenPort: UInt16(3000 + $0)) })
        #expect(many.portsSummary == "5 ports")
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
