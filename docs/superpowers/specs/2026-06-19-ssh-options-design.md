# SSH options + Keychain secrets — design & contract

## Context

Mirrorball currently connects with agent/key auth only and exposes just name,
kind, target, and ports. This adds richer SSH options and secret support:

- **Identity file** (`-i`), **SSH port** (`-p`), **jump host** (`-J`), free-form
  **`-o` options**.
- **Authentication modes**: SSH agent (default), private key file (+ optional
  passphrase), or password.
- **Secrets** (password / key passphrase) stored in the **Keychain** and injected
  into `ssh` via `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force` — never in argv.

## Chosen approach (decided)

- **A: askpass + env hand-off.** Secret lives at rest in the Keychain. On start,
  `AppModel` reads it and the supervisor passes it to a tiny generated askpass
  script via the *ssh child's environment only*. argv stays secret-free.
- **Don't pre-fill** stored secrets into the edit form — show a "stored" state
  with Change/Remove.
- **`SecretStore` protocol** (Keychain in prod, in-memory in tests) so the test
  suite never touches the real Keychain.

## Shared contract (code against these exact symbols)

### Forward (Sources/Core/Forward.swift)
```swift
enum SSHAuthMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case agent, key, password
    var id: String { rawValue }
    var title: String  // "SSH Agent", "Key File", "Password"
}
```
New `Forward` stored fields (all defaulted; tolerant `decodeIfPresent`):
```swift
var authMethod: SSHAuthMethod = .agent
var identityFile: String?     // used when .key
var sshPort: UInt16?          // nil => default 22
var jumpHost: String?
var extraOptions: [String]    // each "Key=Value" => -o Key=Value
```
The memberwise `init` gains these as trailing defaulted params so existing
call sites keep compiling. Secrets are **not** on this type — they live in the
Keychain keyed by `forward.id`.

### SSHArguments.build(for:) — exact order after `commonOptions`:
1. `-p <sshPort>` only if `sshPort != nil && != 22`
2. if `.key` and `identityFile` non-empty: `-i <path>` then `-o IdentitiesOnly=yes`
3. if `jumpHost` non-empty: `-J <jumpHost>`
4. for each non-empty trimmed `extraOptions` line: `-o <line>`
5. if `.password`: `-o PreferredAuthentications=keyboard-interactive,password` then `-o NumberOfPasswordPrompts=1`
Then the existing `-L/-R/-D` spec and the target last. Secret never appears.

### SecretStore (Sources/Core/SecretStore.swift)
```swift
enum SecretUpdate: Sendable, Equatable { case unchanged, clear, set(String) }

protocol SecretStore: Sendable {
    func secret(for id: UUID) -> String?
    func hasSecret(for id: UUID) -> Bool
    func apply(_ update: SecretUpdate, for id: UUID)  // unchanged=noop, clear=delete, set=store
}
struct KeychainSecretStore: SecretStore { init() }          // SecItem generic password,
                                                            // service "co.sanil.mirrorball.secret",
                                                            // account = id.uuidString,
                                                            // kSecAttrAccessibleAfterFirstUnlock
final class InMemorySecretStore: SecretStore, @unchecked Sendable { init() }
```

### AskpassHelper (Sources/Core/AskpassHelper.swift)
```swift
enum AskpassHelper {
    // Writes `#!/bin/sh\nprintf '%s\n' "$MIRRORBALL_ASKPASS_SECRET"\n`, chmod 0755,
    // creating the parent dir. Idempotent.
    static func install(at url: URL) throws
}
```

### TunnelSupervisor (Sources/Core/TunnelSupervisor.swift)
```swift
init(forward: Forward, sshExecutableURL: URL, secret: String? = nil, askpassURL: URL? = nil)
```
In `spawn`, when `secret` and `askpassURL` are both present, set the child's
environment to `ProcessInfo.processInfo.environment` plus:
`SSH_ASKPASS=<askpassURL.path>`, `SSH_ASKPASS_REQUIRE=force`,
`MIRRORBALL_ASKPASS_SECRET=<secret>`. Otherwise leave `environment` unset.

### AppConfiguration (orchestrator)
Adds computed `var askpassScriptURL: URL { configDirectory.appendingPathComponent("askpass.sh") }`.

### AppModel (orchestrator)
- New init param `secretStore: SecretStore = KeychainSecretStore()`; installs the
  askpass script at launch.
- `func hasSecret(for id: UUID) -> Bool`
- `add(_ forward, secret: SecretUpdate = .unchanged)`, `update(_ entry, with:, secret: SecretUpdate = .unchanged)`
- `delete` also clears the entry's secret (`apply(.clear, …)`).
- `startSupervising`: if `authMethod != .agent`, fetch secret from the store and
  pass it (+ `configuration.askpassScriptURL`) to the supervisor.

### Editor (ForwardEditorSheet.swift / DraftForward.swift)
- Authentication section: segmented Agent · Key File · Password.
  - `.key`: identity-file field + "Choose…" (`NSOpenPanel`, default `~/.ssh`,
    hidden files shown) + optional passphrase secret field.
  - `.password`: required password secret field.
  - Secret field: `SecureField`; when editing and `model.hasSecret(for: id)`,
    show prompt "Leave blank to keep stored secret" + a "Remove" button.
- Advanced disclosure: SSH port, jump host, extra `-o` options (one per line).
- `DraftForward` gains the matching fields + `secretInput`, `hasStoredSecret`,
  `clearSecret`; `validate()` enforces: valid port (1–65535) if present; each
  extra-option line contains `=`; `.key` requires an identity file; `.password`
  requires a secret (stored or typed). Expose `secretUpdate() -> SecretUpdate`.

## Tests
- Unit: new argv flags & ordering; `InMemorySecretStore` round-trip; `DraftForward`
  validation incl. secret rules.
- Integration: a fake `ssh` that execs `$SSH_ASKPASS` and only succeeds when it
  receives the expected secret — proving the injection path end-to-end; plus an
  `AppModel` e2e using `InMemorySecretStore` + fake ssh.
```
