<p align="center">
  <h1 align="center">🪩 Mirrorball</h1>
  <p align="center">A dead-simple, native SSH port-forward manager for macOS.</p>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS-blue">
  <img alt="Built with Swift + SwiftUI" src="https://img.shields.io/badge/built%20with-Swift%20%2B%20SwiftUI-orange">
  <img alt="Tests" src="https://img.shields.io/badge/tests-80%2B-brightgreen">
  <img alt="License: GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-green">
</p>

---

Mirrorball turns SSH tunnels into rows with a switch. Flip one on to bring a forward up; if the connection drops — laptop sleep, network blip, server hiccup — it quietly reconnects with backoff; flip it off and it's gone. It lives in your menu bar *and* a proper window, and under the hood it drives the system `ssh` binary, so it reuses your existing `~/.ssh/config`, keys, and agent. Nothing to configure twice.

Built natively in **Swift + SwiftUI** to feel at home on macOS, it goes beyond the basics with first-class authentication — passwords and key passphrases stored securely in your Keychain — and a polished editor for every SSH option you actually reach for.

<!-- Add a screenshot at docs/screenshot.png and uncomment:
<p align="center"><img src="docs/screenshot.png" alt="Mirrorball" width="460"></p>
-->

## Features

- **Menu bar + window** — a status-bar item with quick toggles (the glyph reflects aggregate state at a glance), plus a full management window. Closing the window keeps Mirrorball running in the menu bar.
- **All three forward types** — local (`-L`), remote (`-R`), and dynamic SOCKS (`-D`).
- **Auto-reconnect** — per-forward supervision with exponential backoff (1s → 30s); tunnels survive sleeps and blips. When a connection genuinely fails, the real `ssh` reason is surfaced instead of an endless silent retry.
- **Rich SSH options** — identity file (`-i`), custom port (`-p`), jump host (`-J`), and free-form `-o Key=Value` options.
- **Keychain-backed auth** — choose SSH agent, a private key (with optional passphrase), or a password. Secrets live at rest in the Keychain and are handed to `ssh` via `SSH_ASKPASS` — never on the command line.
- **Uses your SSH setup** — spawns the system `ssh`, inheriting `~/.ssh/config`, keys, and your agent. Host aliases populate the editor's picker.
- **Native throughout** — SwiftUI with system switch controls, grouped forms, SF Symbols, automatic light/dark, a Settings window (⌘,), launch-at-login (`SMAppService`), and native notifications on drops/reconnects/failures.
- **Persists** — forwards live in a small JSON file; enabled ones auto-start on launch. `ssh` children are torn down cleanly on quit, so tunnels never leak.

## Install

### Prerequisites

- **macOS 26+** and **Xcode 26+**.
- [Tuist](https://tuist.dev) (`mise install tuist`, `brew install tuist`, or the install script). The Xcode project is generated from `Project.swift`.
- A working `ssh` client (preinstalled on macOS).

### Build from source

```bash
git clone https://github.com/heysanil/mirrorball.git
cd mirrorball
tuist generate            # generates MirrorballSwift.xcodeproj / .xcworkspace
open MirrorballSwift.xcworkspace
# ⌘R to run, ⌘U to test
```

Prefer the command line?

```bash
xcodebuild -workspace MirrorballSwift.xcworkspace -scheme MirrorballSwift \
  -destination 'platform=macOS' build
```

Mirrorball is **non-sandboxed** by design — it spawns `/usr/bin/ssh` and reads `~/.ssh/config`, neither of which is possible under the App Sandbox. For login-at-login to register reliably, run a signed copy from `/Applications`.

## Usage

1. Launch Mirrorball and click **+** (or press **⌘N**).
2. Pick a type:

   | Type | Flag | What it does |
   |------|------|--------------|
   | **Local** | `-L` | Bind a local port to a service reachable from the server, e.g. `localhost:5432` → `db:5432`. |
   | **Remote** | `-R` | Expose one of *your* local ports on the server. |
   | **Dynamic** | `-D` | A local SOCKS proxy that routes traffic through the server. |

3. Choose an SSH host (an alias from `~/.ssh/config`, or type `user@host`) and set the ports.
4. Pick an **authentication** method — SSH agent, a private key file (+ optional passphrase), or a password. Secrets are saved to your Keychain.
5. Optionally open **Advanced** for a custom SSH port, jump host, or extra `-o` options.
6. Flip the toggle. **Green** = connected, **amber** = connecting/reconnecting, **red** = the connection failed (the real `ssh` reason is shown).

> [!NOTE]
> **Authentication.** Mirrorball runs `ssh` non-interactively. For password and encrypted-key auth it stores the secret in the Keychain and feeds it to `ssh` through an `SSH_ASKPASS` helper (`SSH_ASKPASS_REQUIRE=force`), so the secret never appears in the process arguments.

## Configuration

Forwards are stored as JSON in your Application Support directory:

```
~/Library/Application Support/MirrorballSwift/forwards.json
```

```jsonc
[
  {
    "name": "Prod database",
    "kind": "local",          // local | remote | dynamic
    "target": "prod",         // ssh alias or user@host
    "listenPort": 5432,
    "remoteHost": "localhost", // local/remote only
    "remotePort": 5432,        // local/remote only
    "enabled": true,           // auto-start on launch
    "authMethod": "key",       // agent | key | password
    "identityFile": "~/.ssh/id_ed25519",
    "sshPort": 22,
    "jumpHost": "user@bastion",
    "extraOptions": ["ServerAliveInterval=30"]
  }
]
```

Secrets (passwords / key passphrases) are **not** written here — they live in the Keychain, keyed by the forward's id. Each running forward becomes an `ssh -N … -L/-R/-D …` invocation with `ServerAliveInterval` keepalives and `ExitOnForwardFailure=yes` so failures surface instead of hanging.

## How it works

Each enabled forward gets its own `actor TunnelSupervisor` that owns an `ssh` `Process`, watches it, and respawns it with exponential backoff if it dies while still enabled — publishing status changes over an `AsyncStream`. A single `@MainActor @Observable AppModel` consumes those streams and is shared by both the window and the menu bar through the SwiftUI environment. There is no embedded SSH stack — just your system `ssh`.

```
Sources/
  App/      MirrorballApp (scenes), AppDelegate (lifecycle, child teardown)
  Core/     Forward, ForwardStatus, SSHArguments (pure argv), TunnelSupervisor,
            Persistence, SSHConfigParser, SecretStore (Keychain), AskpassHelper,
            Notifier, LoginItem, AppConfiguration, ChildProcessRegistry, DraftForward
  State/    AppModel (@Observable, @MainActor), ForwardEntry
  Theme/    Palette, Metrics
  Views/    Main/ (window, row, badge, dot), Editor/, MenuBar/, Settings/
  Shared/   AccessibilityIdentifiers (compiled into the UI test target too)
```

## Development

```bash
tuist generate
xcodebuild -workspace MirrorballSwift.xcworkspace -scheme MirrorballSwift \
  -destination 'platform=macOS' \
  -only-testing:MirrorballUnitTests -only-testing:MirrorballIntegrationTests test
```

**80+ tests** across three targets:

- **Unit** — pure logic: `ssh` argv construction, the model, JSON persistence, `~/.ssh/config` parsing, form validation, secret storage.
- **Integration** — the `TunnelSupervisor` against *real* spawned processes, driven by a fake-`ssh` harness (connect / drop / reconnect / fail / askpass injection), plus full `AppModel` end-to-end flows.
- **UI** — XCUITest flows (add / validate / toggle / persist). These need a GUI session with automation permission; Xcode prompts on first run.

Tests use environment hooks so they never touch your real environment:

| Variable | Purpose |
|---|---|
| `MIRRORBALL_SSH_PATH` | Substitute a fake-ssh script for `/usr/bin/ssh` |
| `MIRRORBALL_CONFIG_DIR` | Redirect persistence to a temp directory |
| `MIRRORBALL_DISABLE_SIDE_EFFECTS` | Skip notifications + login-item registration |
| `MIRRORBALL_SEED` | Seed forwards as a JSON array on launch |

Contributions welcome.

## Building & releasing

Releases are built by GitHub Actions on a **Namespace** macOS runner
(`nscloud-macos-tahoe-arm64-6x14`, macOS 26 / Xcode 26). The job produces a
Developer ID-signed, notarized, stapled drag-install DMG
(`Mirrorball.app` + an Applications shortcut).

**Triggers:** push a `v*` tag (e.g. `v1.2.3`) to build and attach the DMG to the
matching GitHub Release, or run the **Release DMG** workflow manually from the
Actions tab (optional `version` input). Every run also uploads the DMG as a
workflow artifact.

### One-time setup

1. **Namespace:** connect `heysanil/mirrorball` to your Namespace tenant and
   enable the macOS runner profile (install the Namespace GitHub App on the repo).
2. **Apple:** you need a paid Apple Developer account, a **Developer ID
   Application** certificate, and an **App Store Connect API key** (`.p8`).

### Required repository secrets

Settings → Secrets and variables → Actions:

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_APP_CERT_P12_BASE64` | `base64` of your exported Developer ID Application `.p12` |
| `DEVELOPER_ID_APP_CERT_PASSWORD` | the `.p12` export password |
| `KEYCHAIN_PASSWORD` | any string — password for the throwaway CI keychain |
| `APPLE_TEAM_ID` | your 10-character Apple Team ID |
| `NOTARY_API_KEY_ID` | App Store Connect API Key ID |
| `NOTARY_API_ISSUER_ID` | App Store Connect Issuer ID |
| `NOTARY_API_KEY_P8_BASE64` | `base64` of the `.p8` API key file |

Generate the base64 values with `base64 -i Certificates.p12 | pbcopy` and
`base64 -i AuthKey_XXXX.p8 | pbcopy`.

### Building locally

`scripts/package-dmg.sh` runs the same pipeline off-CI. Export the signing
secrets as environment variables, then:

```bash
scripts/package-dmg.sh --version 1.2.3              # full: sign + notarize + staple
scripts/package-dmg.sh --version 1.2.3 --no-notarize  # smoke test, skip Apple round-trip
```

The DMG is written to the repository root as `Mirrorball-<version>.dmg` (gitignored).

## License

[GPL-3.0](LICENSE) © Sanil Chawla
