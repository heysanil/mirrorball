import Testing
@testable import Mirrorball

@Suite("SSH argument builder")
struct SSHArgumentsTests {
    private let common = [
        "-N",
        "-o", "ServerAliveInterval=15",
        "-o", "ServerAliveCountMax=3",
        "-o", "ExitOnForwardFailure=yes",
    ]

    private func base(
        kind: ForwardKind = .local,
        target: String = "prod",
        listenPort: UInt16 = 5432,
        remoteHost: String = "localhost",
        remotePort: UInt16 = 5432
    ) -> Forward {
        Forward(
            name: "t",
            kind: kind,
            target: target,
            listenPort: listenPort,
            remoteHost: remoteHost,
            remotePort: remotePort
        )
    }

    @Test("Local forward builds -L listen:host:port + target")
    func localForward() {
        let args = SSHArguments.build(for: base())
        #expect(args == common + ["-L", "5432:localhost:5432", "prod"])
    }

    @Test("Remote forward builds -R listen:host:port + target")
    func remoteForward() {
        let f = base(kind: .remote, listenPort: 8080, remotePort: 3000)
        let args = SSHArguments.build(for: f)
        #expect(args == common + ["-R", "8080:localhost:3000", "prod"])
    }

    @Test("Dynamic forward builds -D listen + target, ignoring remote fields")
    func dynamicForward() {
        let f = base(kind: .dynamic, listenPort: 1080, remoteHost: "ignored", remotePort: 9999)
        let args = SSHArguments.build(for: f)
        #expect(args == common + ["-D", "1080", "prod"])
    }

    @Test("Empty remote host defaults to localhost")
    func emptyRemoteHostDefaults() {
        let f = base(remoteHost: "")
        let args = SSHArguments.build(for: f)
        #expect(args.contains("5432:localhost:5432"))
    }

    @Test("Whitespace remote host is trimmed and defaulted")
    func whitespaceRemoteHost() {
        let f = base(remoteHost: "   ")
        let args = SSHArguments.build(for: f)
        #expect(args.contains("5432:localhost:5432"))
    }

    @Test("Target is always the final argument")
    func targetIsLast() {
        #expect(SSHArguments.build(for: base(target: "user@host.example")).last == "user@host.example")
        #expect(SSHArguments.build(for: base(kind: .dynamic, target: "bastion")).last == "bastion")
    }

    @Test("Multi-mapping local forward emits one -L per mapping in order, target last")
    func multiMappingLocal() {
        let f = Forward(name: "devbox", kind: .local, target: "devbox", mappings: [
            PortMapping(label: "frontend", listenPort: 3000, remoteHost: "localhost", remotePort: 3000),
            PortMapping(label: "backend", listenPort: 8080, remoteHost: "localhost", remotePort: 8080),
            PortMapping(label: "db", listenPort: 5432, remoteHost: "db.internal", remotePort: 5432),
        ])
        let args = SSHArguments.build(for: f)
        #expect(args == common + [
            "-L", "3000:localhost:3000",
            "-L", "8080:localhost:8080",
            "-L", "5432:db.internal:5432",
            "devbox",
        ])
    }

    @Test("Multi-mapping remote forward emits one -R per mapping in order")
    func multiMappingRemote() {
        let f = Forward(name: "r", kind: .remote, target: "edge", mappings: [
            PortMapping(listenPort: 8080, remoteHost: "localhost", remotePort: 3000),
            PortMapping(listenPort: 9090, remoteHost: "localhost", remotePort: 9000),
        ])
        let args = SSHArguments.build(for: f)
        #expect(args == common + [
            "-R", "8080:localhost:3000",
            "-R", "9090:localhost:9000",
            "edge",
        ])
    }

    @Test("Multi-mapping dynamic forward emits one -D per mapping, ignoring remote fields")
    func multiMappingDynamic() {
        let f = Forward(name: "d", kind: .dynamic, target: "bastion", mappings: [
            PortMapping(listenPort: 1080, remoteHost: "ignored", remotePort: 9999),
            PortMapping(listenPort: 1081),
        ])
        let args = SSHArguments.build(for: f)
        #expect(args == common + ["-D", "1080", "-D", "1081", "bastion"])
    }
}
