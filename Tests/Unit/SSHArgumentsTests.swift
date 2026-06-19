import Testing
@testable import MirrorballSwift

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
}
