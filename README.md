# Mirrorball

A native **macOS** SSH port-forward manager, written in Swift + SwiftUI. 🪩

Mirrorball turns SSH tunnels into rows with a switch. Flip one on to bring a
forward up; if the connection drops — laptop sleep, network blip, server hiccup —
it quietly reconnects with backoff; flip it off and it's gone. It wraps the
system `ssh` binary, so it inherits your `~/.ssh/config`, keys, and agent for
free.

This is a Mac-native reimagining of the original Rust/egui
[`port-authority`](https://github.com/heysanil/port-authority) app — same SSH
behavior, rebuilt to feel at home on macOS.

## Features

- **Three forward types** — Local (`-L`), Remote (`-R`), and Dynamic SOCKS (`-D`).
- **Auto-reconnect** with exponential backoff (1s → 30s), resetting after a
  connection stays stable for 10s.
- **Menu bar + window** — a status-bar item with quick toggles, plus a full
  management window. The menu bar glyph reflects aggregate state at a glance.
- **Live status** — connecting / connected / reconnecting / error, with the real
  `ssh` stderr surfaced on failure.
- **`~/.ssh/config` aware** — host aliases populate the editor's host picker.
- **Launch at login** via `SMAppService`, and native **notifications** when a
  tunnel drops, recovers, or fails.
- **Native throughout** — system switch controls, grouped forms, SF Symbols,
  light/dark, and a Settings window (⌘,).

## Architecture

```
Sources/
  App/      MirrorballApp (scenes), AppDelegate (lifecycle, child teardown)
  Core/     Forward, ForwardStatus, SSHArguments, TunnelSupervisor (actor),
            Persistence, SSHConfigParser, Notifier, LoginItem, AppConfiguration,
            ChildProcessRegistry, DraftForward
  State/    AppModel (@Observable, @MainActor), ForwardEntry
  Theme/    Palette, Metrics
  Views/    Main/ (window, row, badge, dot), Editor/, MenuBar/, Settings/
  Shared/   AccessibilityIdentifiers (compiled into the UI test target too)
```

- One **`actor TunnelSupervisor` per forward** owns its `Process` and the
  reconnect state machine, publishing status over an `AsyncStream`.
- A single **`@MainActor @Observable AppModel`** consumes those streams and is
  shared by both the window and the menu bar via the SwiftUI environment.
- `ssh` children are tracked in a `ChildProcessRegistry` and torn down on quit,
  so tunnels never leak as orphaned processes.

## Build & run

Requires Xcode 26+ and [Tuist](https://tuist.dev).

```sh
tuist generate     # generates MirrorballSwift.xcodeproj/.xcworkspace
open MirrorballSwift.xcworkspace
# ⌘R to run, ⌘U to test
```

Or from the command line:

```sh
xcodebuild -workspace MirrorballSwift.xcworkspace -scheme MirrorballSwift \
  -destination 'platform=macOS' build
```

The app is **non-sandboxed** by design (it spawns `/usr/bin/ssh` and reads
`~/.ssh/config`). For login-at-login to be reliable, run a signed copy from
`/Applications`.

## Testing

```sh
# Headless: pure logic + supervisor + full AppModel end-to-end (fake-ssh harness)
xcodebuild -workspace MirrorballSwift.xcworkspace -scheme MirrorballSwift \
  -destination 'platform=macOS' \
  -only-testing:MirrorballUnitTests -only-testing:MirrorballIntegrationTests test

# UI e2e (needs a GUI session + automation permission; Xcode prompts on first run)
xcodebuild ... -only-testing:MirrorballUITests test
```

Tests use environment hooks so they never touch your real environment:

| Variable | Purpose |
|---|---|
| `MIRRORBALL_SSH_PATH` | Substitute a fake-ssh script for `/usr/bin/ssh` |
| `MIRRORBALL_CONFIG_DIR` | Redirect persistence to a temp directory |
| `MIRRORBALL_DISABLE_SIDE_EFFECTS` | Skip notifications + login-item registration |
| `MIRRORBALL_SEED` | Seed forwards as a JSON array on launch |

Config is stored as JSON at
`~/Library/Application Support/MirrorballSwift/forwards.json`.
