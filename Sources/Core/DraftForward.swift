import Foundation

/// A human-readable reason the draft can't be saved yet, shown inline in the editor.
struct ValidationError: Error, Equatable {
    let message: String
}

/// Editable, string-backed form state for one port mapping inside the editor.
/// Ports stay strings while typing and are only parsed on save.
struct DraftPortMapping: Equatable, Identifiable {
    var id = UUID()
    var label = ""
    var listenPort = ""
    var remoteHost = "localhost"
    var remotePort = ""
}

/// Editable, string-backed form state for the editor. Ports are strings while
/// typing and only parsed/validated on save, which keeps the fields forgiving.
/// `validate()` is pure so it can be unit-tested without any UI.
struct DraftForward: Equatable {
    var name = ""
    var kind: ForwardKind = .local
    var target = ""
    /// One or more port mappings carried over this connection. Starts with one.
    var mappings: [DraftPortMapping] = [DraftPortMapping()]
    var enabled = true

    // Authentication + advanced options.
    var authMethod: SSHAuthMethod = .agent
    var identityFile = ""
    var sshPort = ""
    var jumpHost = ""
    var extraOptions = ""

    // Transient secret editing state. We never read a stored secret back into the
    // form; `hasStoredSecret` only signals that one exists so the UI can show a
    // "leave blank to keep" affordance.
    var secretInput = ""
    var hasStoredSecret = false
    var clearSecret = false

    init() {}

    init(_ forward: Forward) {
        name = forward.name
        kind = forward.kind
        target = forward.target
        mappings = forward.mappings.map { mapping in
            DraftPortMapping(
                label: mapping.label,
                listenPort: String(mapping.listenPort),
                remoteHost: mapping.remoteHost,
                remotePort: forward.kind.usesRemoteEndpoint ? String(mapping.remotePort) : ""
            )
        }
        enabled = forward.enabled
        authMethod = forward.authMethod
        identityFile = forward.identityFile ?? ""
        sshPort = forward.sshPort.map(String.init) ?? ""
        jumpHost = forward.jumpHost ?? ""
        extraOptions = forward.extraOptions.joined(separator: "\n")
    }

    /// Validate and produce a `Forward`, or a human-readable error to show inline.
    func validate() -> Result<Forward, ValidationError> {
        func fail(_ message: String) -> Result<Forward, ValidationError> {
            .failure(ValidationError(message: message))
        }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            return fail("Give this forward a name.")
        }

        let trimmedTarget = target.trimmingCharacters(in: .whitespaces)
        guard !trimmedTarget.isEmpty else {
            return fail("Enter an SSH host — an alias from ~/.ssh/config or user@host.")
        }

        guard !mappings.isEmpty else {
            return fail("Add at least one port to forward.")
        }

        // Resolve every mapping, applying smart defaults and rejecting any port
        // bound twice within this one connection.
        var resolvedMappings: [PortMapping] = []
        var seenListenPorts = Set<UInt16>()

        for mapping in mappings {
            guard let listen = port(from: mapping.listenPort) else {
                return fail("\(listenPortLabel) must be a number from 1 to 65535.")
            }
            guard seenListenPorts.insert(listen).inserted else {
                return fail("Port \(listen) is forwarded more than once.")
            }

            var resolvedRemoteHost = "localhost"
            var resolvedRemotePort: UInt16 = 0

            if kind.usesRemoteEndpoint {
                // Smart default: a blank destination port mirrors the listen port.
                let trimmedRemotePort = mapping.remotePort.trimmingCharacters(in: .whitespaces)
                if trimmedRemotePort.isEmpty {
                    resolvedRemotePort = listen
                } else {
                    guard let remote = port(from: trimmedRemotePort) else {
                        return fail("Destination port must be a number from 1 to 65535.")
                    }
                    resolvedRemotePort = remote
                }
                // Smart default: a blank/whitespace host means the server itself.
                let host = mapping.remoteHost.trimmingCharacters(in: .whitespaces)
                resolvedRemoteHost = host.isEmpty ? "localhost" : host
            }

            resolvedMappings.append(
                PortMapping(
                    label: mapping.label.trimmingCharacters(in: .whitespaces),
                    listenPort: listen,
                    remoteHost: resolvedRemoteHost,
                    remotePort: resolvedRemotePort
                )
            )
        }

        // Optional SSH server port.
        var resolvedSSHPort: UInt16?
        let trimmedSSHPort = sshPort.trimmingCharacters(in: .whitespaces)
        if !trimmedSSHPort.isEmpty {
            guard let parsed = port(from: trimmedSSHPort) else {
                return fail("SSH port must be a number from 1 to 65535.")
            }
            resolvedSSHPort = parsed
        }

        // Extra -o options: one Key=Value per line.
        var resolvedOptions: [String] = []
        for line in extraOptions.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard trimmed.contains("=") else {
                return fail("Each extra option must be in Key=Value form (e.g. ServerAliveInterval=30).")
            }
            resolvedOptions.append(trimmed)
        }

        // Auth-method-specific requirements.
        let trimmedIdentity = identityFile.trimmingCharacters(in: .whitespaces)
        if authMethod == .key, trimmedIdentity.isEmpty {
            return fail("Choose a private key file for key authentication.")
        }
        let willHaveSecret = !secretInput.isEmpty || (hasStoredSecret && !clearSecret)
        if authMethod == .password, !willHaveSecret {
            return fail("Enter a password for password authentication.")
        }

        let trimmedJump = jumpHost.trimmingCharacters(in: .whitespaces)

        return .success(
            Forward(
                name: trimmedName,
                kind: kind,
                target: trimmedTarget,
                mappings: resolvedMappings,
                enabled: enabled,
                authMethod: authMethod,
                identityFile: authMethod == .key && !trimmedIdentity.isEmpty ? trimmedIdentity : nil,
                sshPort: resolvedSSHPort,
                jumpHost: trimmedJump.isEmpty ? nil : trimmedJump,
                extraOptions: resolvedOptions
            )
        )
    }

    /// What to do with the stored secret when saving.
    func secretUpdate() -> SecretUpdate {
        if clearSecret { return .clear }
        if !secretInput.isEmpty { return .set(secretInput) }
        return .unchanged
    }

    /// Field label that changes with the kind (we bind on the server for `-R`).
    var listenPortLabel: String {
        switch kind {
        case .local, .dynamic: "Local port"
        case .remote: "Remote bind port"
        }
    }

    private func port(from string: String) -> UInt16? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard let value = UInt16(trimmed), value > 0 else { return nil }
        return value
    }
}
