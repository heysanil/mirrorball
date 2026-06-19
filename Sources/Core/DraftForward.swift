import Foundation

/// A human-readable reason the draft can't be saved yet, shown inline in the editor.
struct ValidationError: Error, Equatable {
    let message: String
}

/// Editable, string-backed form state for the editor. Ports are strings while
/// typing and only parsed/validated on save, which keeps the fields forgiving.
/// `validate()` is pure so it can be unit-tested without any UI.
struct DraftForward: Equatable {
    var name = ""
    var kind: ForwardKind = .local
    var target = ""
    var listenPort = ""
    var remoteHost = "localhost"
    var remotePort = ""
    var enabled = true

    init() {}

    init(_ forward: Forward) {
        name = forward.name
        kind = forward.kind
        target = forward.target
        listenPort = String(forward.listenPort)
        remoteHost = forward.remoteHost
        remotePort = forward.kind.usesRemoteEndpoint ? String(forward.remotePort) : ""
        enabled = forward.enabled
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

        guard let listen = port(from: listenPort) else {
            return fail("\(listenPortLabel) must be a number from 1 to 65535.")
        }

        var resolvedRemoteHost = "localhost"
        var resolvedRemotePort: UInt16 = 0

        if kind.usesRemoteEndpoint {
            guard let remote = port(from: remotePort) else {
                return fail("Destination port must be a number from 1 to 65535.")
            }
            resolvedRemotePort = remote
            let host = remoteHost.trimmingCharacters(in: .whitespaces)
            resolvedRemoteHost = host.isEmpty ? "localhost" : host
        }

        return .success(
            Forward(
                name: trimmedName,
                kind: kind,
                target: trimmedTarget,
                listenPort: listen,
                remoteHost: resolvedRemoteHost,
                remotePort: resolvedRemotePort,
                enabled: enabled
            )
        )
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
