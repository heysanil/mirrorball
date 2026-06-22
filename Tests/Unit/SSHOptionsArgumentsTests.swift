import Testing
@testable import Mirrorball

@Suite("SSH argument builder — options")
struct SSHOptionsArgumentsTests {
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
        remotePort: UInt16 = 5432,
        authMethod: SSHAuthMethod = .agent,
        identityFile: String? = nil,
        sshPort: UInt16? = nil,
        jumpHost: String? = nil,
        extraOptions: [String] = []
    ) -> Forward {
        Forward(
            name: "t",
            kind: kind,
            target: target,
            listenPort: listenPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            authMethod: authMethod,
            identityFile: identityFile,
            sshPort: sshPort,
            jumpHost: jumpHost,
            extraOptions: extraOptions
        )
    }

    @Test("Default agent auth adds none of the new flags")
    func agentDefaultAddsNothing() {
        // Same output as the pre-options builder for a plain local forward.
        let args = SSHArguments.build(for: base())
        #expect(args == common + ["-L", "5432:localhost:5432", "prod"])
    }

    @Test("An identity file with .agent auth is ignored (no -i)")
    func agentIgnoresIdentityFile() {
        let args = SSHArguments.build(for: base(identityFile: "~/.ssh/id_ed25519"))
        #expect(!args.contains("-i"))
        #expect(args == common + ["-L", "5432:localhost:5432", "prod"])
    }

    @Test("sshPort 2222 adds -p 2222")
    func nonDefaultPortAddsFlag() {
        let args = SSHArguments.build(for: base(sshPort: 2222))
        #expect(adjacent(args, "-p", "2222"))
    }

    @Test("sshPort 22 and nil add no -p")
    func defaultPortAddsNothing() {
        #expect(!SSHArguments.build(for: base(sshPort: 22)).contains("-p"))
        #expect(!SSHArguments.build(for: base(sshPort: nil)).contains("-p"))
    }

    @Test(".key with identity file adds -i then -o IdentitiesOnly=yes")
    func keyAuthAddsIdentity() {
        let args = SSHArguments.build(for: base(authMethod: .key, identityFile: "~/.ssh/id_ed25519"))
        #expect(adjacent(args, "-i", "~/.ssh/id_ed25519"))
        // IdentitiesOnly immediately follows the -i pair.
        let iIndex = args.firstIndex(of: "-i")!
        #expect(args[iIndex + 2] == "-o")
        #expect(args[iIndex + 3] == "IdentitiesOnly=yes")
    }

    @Test(".key with blank identity file adds no -i")
    func keyAuthBlankIdentitySkipped() {
        let args = SSHArguments.build(for: base(authMethod: .key, identityFile: "   "))
        #expect(!args.contains("-i"))
        #expect(!args.contains("IdentitiesOnly=yes"))
    }

    @Test("jumpHost adds -J user@bastion")
    func jumpHostAddsFlag() {
        let args = SSHArguments.build(for: base(jumpHost: "user@bastion"))
        #expect(adjacent(args, "-J", "user@bastion"))
    }

    @Test("extraOptions add -o per non-blank line and skip blanks")
    func extraOptionsAddedAndTrimmed() {
        let args = SSHArguments.build(for: base(extraOptions: ["Compression=yes", "  ", "TCPKeepAlive=yes"]))
        #expect(adjacent(args, "-o", "Compression=yes"))
        #expect(adjacent(args, "-o", "TCPKeepAlive=yes"))
        // The blank line produced no extra -o (only the two we added beyond the common opts).
        let optionValues = oValues(args)
        #expect(!optionValues.contains(""))
        #expect(optionValues.contains("Compression=yes"))
        #expect(optionValues.contains("TCPKeepAlive=yes"))
    }

    @Test(".password adds the two password -o options")
    func passwordAuthAddsOptions() {
        let args = SSHArguments.build(for: base(authMethod: .password))
        #expect(adjacent(args, "-o", "PreferredAuthentications=keyboard-interactive,password"))
        #expect(adjacent(args, "-o", "NumberOfPasswordPrompts=1"))
    }

    @Test("New options sit after common opts and before the -L spec + target")
    func orderingIsExact() {
        let f = base(
            kind: .local,
            target: "prod",
            listenPort: 5432,
            remotePort: 5432,
            authMethod: .key,
            identityFile: "~/.ssh/id_ed25519",
            sshPort: 2222,
            jumpHost: "user@bastion",
            extraOptions: ["Compression=yes"]
        )
        let args = SSHArguments.build(for: f)
        #expect(args == common + [
            "-p", "2222",
            "-i", "~/.ssh/id_ed25519",
            "-o", "IdentitiesOnly=yes",
            "-J", "user@bastion",
            "-o", "Compression=yes",
            "-L", "5432:localhost:5432",
            "prod",
        ])
    }

    // MARK: - Helpers

    /// True if `first` appears immediately followed by `second` somewhere in `args`.
    private func adjacent(_ args: [String], _ first: String, _ second: String) -> Bool {
        for i in args.indices.dropLast() where args[i] == first && args[i + 1] == second {
            return true
        }
        return false
    }

    /// Values that immediately follow each `-o` flag.
    private func oValues(_ args: [String]) -> [String] {
        var values: [String] = []
        for i in args.indices.dropLast() where args[i] == "-o" {
            values.append(args[i + 1])
        }
        return values
    }
}
