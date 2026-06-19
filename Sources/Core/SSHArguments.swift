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
        let remoteHost = forward.effectiveRemoteHost

        switch forward.kind {
        case .local:
            args.append("-L")
            args.append("\(forward.listenPort):\(remoteHost):\(forward.remotePort)")
        case .remote:
            args.append("-R")
            args.append("\(forward.listenPort):\(remoteHost):\(forward.remotePort)")
        case .dynamic:
            args.append("-D")
            args.append("\(forward.listenPort)")
        }

        args.append(forward.target)
        return args
    }
}
