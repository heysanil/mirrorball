import Foundation

/// The three SSH forwarding flavors, mapping to `ssh`'s `-L`, `-R`, `-D` flags.
enum ForwardKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// `-L` — bind a local port; traffic goes to a host reachable from the server.
    case local
    /// `-R` — bind a port *on the server*; traffic comes back to us.
    case remote
    /// `-D` — local SOCKS proxy routing arbitrary traffic through the server.
    case dynamic

    var id: String { rawValue }

    /// Short uppercase pill shown on a row.
    var badge: String {
        switch self {
        case .local: "LOCAL"
        case .remote: "REMOTE"
        case .dynamic: "SOCKS"
        }
    }

    /// Human title used in pickers.
    var title: String {
        switch self {
        case .local: "Local"
        case .remote: "Remote"
        case .dynamic: "Dynamic"
        }
    }

    /// One-line explanation surfaced in the editor.
    var explanation: String {
        switch self {
        case .local: "Reach a remote service as if it were on this Mac."
        case .remote: "Expose one of this Mac's ports on the server."
        case .dynamic: "Run a local SOCKS proxy through the server."
        }
    }

    /// SF Symbol that reads well for the kind.
    var symbol: String {
        switch self {
        case .local: "arrow.down.left.circle"
        case .remote: "arrow.up.right.circle"
        case .dynamic: "globe"
        }
    }

    /// Local/Remote forward to a `host:port`; Dynamic only binds a listen port.
    var usesRemoteEndpoint: Bool { self != .dynamic }
}

/// How `ssh` should authenticate for a forward. The secret itself (password or
/// key passphrase) never lives on `Forward` — it is kept in the Keychain and
/// injected via askpass at spawn time.
enum SSHAuthMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Default — let the running SSH agent provide credentials.
    case agent
    /// Authenticate with a private key file (`-i`), optional passphrase.
    case key
    /// Keyboard-interactive / password authentication.
    case password

    var id: String { rawValue }

    /// Human title used in the authentication picker.
    var title: String {
        switch self {
        case .agent: "SSH Agent"
        case .key: "Key File"
        case .password: "Password"
        }
    }
}

/// A single forward definition. Persisted verbatim to disk as JSON.
///
/// A stable `id` is carried so SwiftUI lists and on-disk records keep identity
/// across edits and reorders. `Status` is *not* part of this type — it is
/// transient runtime state owned by the supervisor.
struct Forward: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var kind: ForwardKind
    /// Whatever you'd type after `ssh`: a `~/.ssh/config` alias or `user@host`.
    var target: String
    /// The port we bind (locally for `-L`/`-D`, on the server for `-R`).
    var listenPort: UInt16
    /// Destination host as seen from the *other* end. Unused for `.dynamic`.
    var remoteHost: String
    /// Destination port. Unused for `.dynamic`.
    var remotePort: UInt16
    /// Whether this forward auto-starts on launch and is currently meant to run.
    var enabled: Bool
    /// How `ssh` authenticates. Defaults to the SSH agent.
    var authMethod: SSHAuthMethod
    /// Path to the private key file, used when `authMethod == .key`.
    var identityFile: String?
    /// SSH server port (`-p`). `nil` (or 22) means the default port.
    var sshPort: UInt16?
    /// Optional jump/bastion host (`-J`), e.g. `user@bastion`.
    var jumpHost: String?
    /// Free-form `-o Key=Value` options, one entry per line.
    var extraOptions: [String]

    init(
        id: UUID = UUID(),
        name: String,
        kind: ForwardKind,
        target: String,
        listenPort: UInt16,
        remoteHost: String = "localhost",
        remotePort: UInt16 = 0,
        enabled: Bool = false,
        authMethod: SSHAuthMethod = .agent,
        identityFile: String? = nil,
        sshPort: UInt16? = nil,
        jumpHost: String? = nil,
        extraOptions: [String] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.target = target
        self.listenPort = listenPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.enabled = enabled
        self.authMethod = authMethod
        self.identityFile = identityFile
        self.sshPort = sshPort
        self.jumpHost = jumpHost
        self.extraOptions = extraOptions
    }

    // Tolerant decoding: a hand-edited record missing `id` still loads (we mint a
    // fresh one) rather than failing the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(ForwardKind.self, forKey: .kind)
        target = try c.decode(String.self, forKey: .target)
        listenPort = try c.decode(UInt16.self, forKey: .listenPort)
        remoteHost = try c.decodeIfPresent(String.self, forKey: .remoteHost) ?? "localhost"
        remotePort = try c.decodeIfPresent(UInt16.self, forKey: .remotePort) ?? 0
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        authMethod = try c.decodeIfPresent(SSHAuthMethod.self, forKey: .authMethod) ?? .agent
        identityFile = try c.decodeIfPresent(String.self, forKey: .identityFile)
        sshPort = try c.decodeIfPresent(UInt16.self, forKey: .sshPort)
        jumpHost = try c.decodeIfPresent(String.self, forKey: .jumpHost)
        extraOptions = try c.decodeIfPresent([String].self, forKey: .extraOptions) ?? []
    }
}

extension Forward {
    /// The effective destination host, defaulting an empty value to `localhost`
    /// (matches the argv builder so the editor preview and the real command agree).
    var effectiveRemoteHost: String {
        let trimmed = remoteHost.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "localhost" : trimmed
    }

    /// Compact "what maps where" string for a row, e.g. `:5432 → db:5432`.
    ///
    /// The bind side is shown as a bare `:port` (it's always on this Mac for
    /// `-L`/`-D`, on the server for `-R` where it's labelled `server:`), so it
    /// reads distinctly from the destination `host:port` — which for `-L` is
    /// resolved on the *far* end, hence often `localhost` (the server itself).
    /// The SSH host the tunnel runs over is the separate `target` shown alongside.
    var mappingDescription: String {
        switch kind {
        case .local:
            ":\(listenPort) → \(effectiveRemoteHost):\(remotePort)"
        case .remote:
            "server:\(listenPort) → \(effectiveRemoteHost):\(remotePort)"
        case .dynamic:
            "SOCKS proxy on :\(listenPort)"
        }
    }
}
