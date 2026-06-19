import Foundation
import Security

/// How a secret (password or key passphrase) should change when a forward is
/// saved. Editing never pre-fills the stored secret, so the editor reports its
/// *intent* — keep what's there, wipe it, or replace it — rather than the value.
///
/// `unchanged` is the default so existing call sites and untouched edits leave
/// the Keychain alone.
enum SecretUpdate: Sendable, Equatable {
    /// Leave any stored secret as-is (the common "I only edited ports" case).
    case unchanged
    /// Remove the stored secret entirely.
    case clear
    /// Store this value, replacing anything already there.
    case set(String)
}

/// Abstracts where a forward's secret lives so production can use the Keychain
/// while tests use an in-memory double — the suite must never touch the real
/// Keychain (it would prompt or fail in CI). Keyed by the forward's `id`.
protocol SecretStore: Sendable {
    /// The stored secret for `id`, or `nil` if none exists / it can't be read.
    func secret(for id: UUID) -> String?
    /// Whether a secret is stored for `id`. Drives the editor's "stored" state.
    func hasSecret(for id: UUID) -> Bool
    /// Apply an editor's intent: `unchanged` no-ops, `clear` deletes, `set` stores.
    func apply(_ update: SecretUpdate, for id: UUID)
}

extension SecretStore {
    /// Default: presence is "can we read a value back". Stores may override if
    /// they can answer more cheaply.
    func hasSecret(for id: UUID) -> Bool { secret(for: id) != nil }
}

/// The production store. Persists secrets as Keychain generic-password items so
/// they sit at rest in the user's encrypted Keychain and never appear in argv.
///
/// Every item shares one service and is distinguished by account = the forward's
/// UUID string. All Security calls are best-effort: an `OSStatus` failure yields
/// `nil`/no-op rather than crashing, so a quirky Keychain never wedges the app.
struct KeychainSecretStore: SecretStore {
    /// Shared service identifier; the account field carries the per-forward UUID.
    private static let service = "co.sanil.mirrorball.secret"

    init() {}

    func secret(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    func apply(_ update: SecretUpdate, for id: UUID) {
        switch update {
        case .unchanged:
            break
        case .clear:
            delete(id)
        case .set(let value):
            // Delete-then-add keeps this idempotent regardless of prior state,
            // sidestepping the add-vs-update branching SecItem otherwise needs.
            delete(id)
            guard let data = value.data(using: .utf8) else { return }
            let attributes: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.service,
                kSecAttrAccount as String: id.uuidString,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            _ = SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    /// Remove the item for `id`, treating "wasn't there" as success.
    private func delete(_ id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound is expected and fine; any other error we ignore by
        // design — a failed delete must not crash the app.
        _ = status
    }
}

/// A thread-safe in-memory store used by tests so the suite never touches the
/// real Keychain. `@unchecked Sendable` because the mutable dictionary is
/// guarded by an explicit lock rather than the actor model.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: String] = [:]

    init() {}

    func secret(for id: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[id]
    }

    func apply(_ update: SecretUpdate, for id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        switch update {
        case .unchanged:
            break
        case .clear:
            storage[id] = nil
        case .set(let value):
            storage[id] = value
        }
    }
}
