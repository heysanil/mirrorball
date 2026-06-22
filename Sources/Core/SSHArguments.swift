import Foundation

/// Pure translation from a `Forward` into the `ssh` argument vector.
///
/// Kept free of any I/O so it is trivially unit-testable: given a `Forward`, it
/// returns exactly the args we'd pass to `ssh`. The supervisor owns the actual
/// process spawning.
enum SSHArguments {
    /// Flags applied to every invocation:
    /// - `-N` no remote command, just forward.
    /// - `ServerAliveInterval`/`ServerAliveCountMax` make ssh notice a dead link
    ///   (~45s) so the supervisor can respawn instead of hanging forever.
    /// - `ExitOnForwardFailure=yes` makes ssh exit *fast* if it can't bind the
    ///   port, surfacing a real error instead of a silently-dead tunnel.
    static let commonOptions: [String] = [
        "-N",
        "-o", "ServerAliveInterval=15",
        "-o", "ServerAliveCountMax=3",
        "-o", "ExitOnForwardFailure=yes",
    ]

    /// Build the full `ssh` argument list for a forward (everything after `ssh`).
    static func build(for forward: Forward) -> [String] {
        var args = commonOptions

        // Non-default SSH server port (`-p`). Port 22 is the default, so omit it.
        if let port = forward.sshPort, port != 22 {
            args.append("-p")
            args.append("\(port)")
        }

        // Private-key auth (`-i`). `IdentitiesOnly=yes` stops ssh from also
        // offering agent keys, so we use exactly the file the user picked.
        if forward.authMethod == .key {
            let identity = (forward.identityFile ?? "").trimmingCharacters(in: .whitespaces)
            if !identity.isEmpty {
                args.append("-i")
                args.append(identity)
                args.append("-o")
                args.append("IdentitiesOnly=yes")
            }
        }

        // Jump/bastion host (`-J`).
        let jump = (forward.jumpHost ?? "").trimmingCharacters(in: .whitespaces)
        if !jump.isEmpty {
            args.append("-J")
            args.append(jump)
        }

        // Free-form `-o Key=Value` options, skipping blank lines.
        for option in forward.extraOptions {
            let trimmed = option.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                args.append("-o")
                args.append(trimmed)
            }
        }

        // Password auth: steer ssh toward interactive/password and cap the
        // prompt count so a wrong secret fails fast instead of re-prompting.
        if forward.authMethod == .password {
            args.append("-o")
            args.append("PreferredAuthentications=keyboard-interactive,password")
            args.append("-o")
            args.append("NumberOfPasswordPrompts=1")
        }

        // One forwarding spec per mapping, in list order, so a single ssh
        // process multiplexes every port the connection carries.
        for mapping in forward.mappings {
            switch forward.kind {
            case .local:
                args.append("-L")
                args.append("\(mapping.listenPort):\(mapping.effectiveRemoteHost):\(mapping.remotePort)")
            case .remote:
                args.append("-R")
                args.append("\(mapping.listenPort):\(mapping.effectiveRemoteHost):\(mapping.remotePort)")
            case .dynamic:
                args.append("-D")
                args.append("\(mapping.listenPort)")
            }
        }

        args.append(forward.target)
        return args
    }
}
