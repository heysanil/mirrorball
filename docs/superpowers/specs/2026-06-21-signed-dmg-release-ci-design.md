# Signed-DMG release CI on Namespace runners — design & contract

## Context

Mirrorball has no CI. It ships as an ad-hoc-signed app (`CODE_SIGN_IDENTITY = "-"`
in `Project.swift`), which runs on the build machine but is blocked by Gatekeeper
on any other Mac. This adds a GitHub Actions workflow, running on **Namespace**
macOS runners, that produces a **distributable DMG**: a Developer ID-signed,
notarized, stapled `Mirrorball.app` packaged in the classic drag-to-install layout
(the app icon next to an **Applications folder shortcut**).

The `.xcodeproj`/`.xcworkspace` are Tuist-generated and gitignored, so CI must run
`tuist generate` before it can build.

## Decisions (locked)

- **Signing depth:** full **Developer ID Application** signing → **notarize** →
  **staple**. The only path that yields a DMG that opens with no Gatekeeper warning
  on any Mac.
- **Notary credential:** App Store Connect **API key** (`.p8`) — Key ID + Issuer ID
  + base64 key. Not tied to a personal Apple ID; Apple's recommended CI path.
- **Triggers:** push of a `v*` tag **and** manual `workflow_dispatch` (optional
  `version` input).
- **Output:** **both** — always upload a workflow artifact, and on a `v*` tag also
  attach the DMG to the matching GitHub Release.
- **Runner:** `nscloud-macos-tahoe-arm64-6x14` (macOS 26 / Xcode 26, arm64).
- **No `Project.swift` changes:** Developer ID signing is applied at *export* time,
  preserving the `CODE_SIGN_IDENTITY = "-"` default, the hardened-runtime setting,
  and the non-sandbox invariant.
- **Notarize + staple the DMG only** (single submission, standard for drag-install
  DMGs). Stapling the inner `.app` for offline first-launch is an explicit non-goal.
- **No custom DMG background image** — clean default `create-dmg` window.

## Architecture

A thin workflow delegates the build/sign/package logic to a committed, locally
runnable shell script, so the same packaging can be reproduced and debugged off-CI:

```
.github/workflows/release.yml   ── triggers, runner, secrets → env, artifact/release upload
        │ calls
        ▼
scripts/package-dmg.sh          ── tuist generate → archive → export(Developer ID)
        │                           → create-dmg (app + Applications shortcut)
        │                           → notarytool submit --wait → stapler staple
        ▼
.github/ExportOptions.plist     ── method=developer-id, manual signing, Team ID injected
```

## Contract

### Runner & toolchain
- `runs-on: nscloud-macos-tahoe-arm64-6x14`.
- Select **Xcode 26** explicitly (`sudo xcode-select -s` / `maxim-lobanov/setup-xcode`
  if multiple Xcodes exist), `xcodebuild -runFirstLaunch`.
- Install **Tuist** (mise or Homebrew) and **`create-dmg`** (`brew install create-dmg`,
  the `create-dmg/create-dmg` shell tool that supports `--app-drop-link`).
- **Prerequisite (one-time, outside this repo):** `heysanil/mirrorball` connected to
  a Namespace tenant with the macOS profile enabled (Namespace GitHub App installed).

### Secrets (Settings → Secrets and variables → Actions)
| Secret | Meaning |
|---|---|
| `DEVELOPER_ID_APP_CERT_P12_BASE64` | base64 of the exported Developer ID Application `.p12` |
| `DEVELOPER_ID_APP_CERT_PASSWORD` | `.p12` export password |
| `KEYCHAIN_PASSWORD` | password for the throwaway CI keychain (any string) |
| `APPLE_TEAM_ID` | 10-char Team ID (Developer ID export signing) |
| `NOTARY_API_KEY_ID` | App Store Connect API Key ID |
| `NOTARY_API_ISSUER_ID` | App Store Connect Issuer ID |
| `NOTARY_API_KEY_P8_BASE64` | base64 of the `.p8` API key |

### `scripts/package-dmg.sh` (locally runnable; pure-ish, env-driven)
Inputs via env (mirrors the secrets above) plus:
- `VERSION` — version string for the artifact name (no leading `v`).
- `--no-notarize` flag — build + sign + DMG, skip the Apple round-trip (local smoke test).

Steps, in order:
1. `tuist generate`.
2. Import `DEVELOPER_ID_APP_CERT_P12_BASE64` into a temporary keychain; set partition
   list for non-interactive `codesign`. (In CI, `apple-actions/import-codesign-certs`
   may do this instead; the script keeps a `security`-CLI path for local use.)
3. `xcodebuild archive -workspace MirrorballSwift.xcworkspace -scheme MirrorballSwift
   -configuration Release -destination 'generic/platform=macOS' -archivePath <path>`.
4. `xcodebuild -exportArchive` with `.github/ExportOptions.plist` (`method=developer-id`,
   `signingStyle=manual`, `teamID` injected from `APPLE_TEAM_ID` via PlistBuddy) →
   exports a Developer ID-signed, hardened-runtime `Mirrorball.app`.
5. `create-dmg --volname "Mirrorball" --app-drop-link <x> <y> --icon "Mirrorball.app" <x> <y>
   --codesign "Developer ID Application" "Mirrorball-$VERSION.dmg" <export-dir>` →
   drag-install window with the app icon + Applications shortcut, signed DMG.
6. Unless `--no-notarize`: `xcrun notarytool submit "Mirrorball-$VERSION.dmg"
   --key <p8> --key-id $NOTARY_API_KEY_ID --issuer $NOTARY_API_ISSUER_ID --wait`,
   then `xcrun stapler staple "Mirrorball-$VERSION.dmg"`.
7. Emit the DMG path (e.g. to `$GITHUB_OUTPUT` when run in CI).

### `.github/ExportOptions.plist`
```
method            = developer-id
signingStyle      = manual
teamID            = <injected at runtime from APPLE_TEAM_ID>
signingCertificate = Developer ID Application
```

### Version derivation
- Tag build: `VERSION` = tag minus leading `v` (`v1.2.3` → `1.2.3`); pass
  `MARKETING_VERSION=$VERSION` (+ `CURRENT_PROJECT_VERSION` = run number) to `xcodebuild`.
- Manual build: `VERSION` = `workflow_dispatch` input, default = `Project.swift`'s
  `MARKETING_VERSION`; DMG name may include the short SHA.

### Output
- Always: `actions/upload-artifact` of `Mirrorball-<version>.dmg`.
- Tag (`startsWith(github.ref, 'refs/tags/v')`): create/update the matching Release
  and attach the DMG (`softprops/action-gh-release` or `gh release upload`).

### Docs
- README gains a **"Building & releasing"** section: the secrets table, the one-time
  Namespace + Apple Developer setup, and how to run `scripts/package-dmg.sh` locally.

## Verification

- The script runs end-to-end locally with real creds — the primary functional test.
- `scripts/package-dmg.sh --no-notarize` smoke-tests build + DMG with no Apple round-trip.
- Acceptance: first CI run on a throwaway `v0.0.1-test` tag, then on the produced DMG:
  `xcrun stapler validate Mirrorball-0.0.1-test.dmg` and
  `spctl -a -t open --context context:primary-signature -vv Mirrorball-0.0.1-test.dmg`
  (and `spctl -a -vv` on the mounted `.app`) must report `accepted` / `Notarized`.

## Risks / open verification points

1. **Xcode 26 on the Tahoe image** — the build needs the macOS 26 SDK + Swift 6.2.
   If the image carries multiple Xcodes, pin 26 explicitly; if it lacks 26, the build
   fails fast. This is the highest-risk assumption to confirm on the first run.
2. **Namespace tenant connection** — without the macOS profile enabled on the repo,
   the job never schedules. One-time account setup, documented in the README.
3. **Notarization latency** — `--wait` can take minutes; acceptable for a release job.
4. **Offline first-launch** — only the DMG is stapled, not the inner `.app`; an
   offline first launch after copying to /Applications may hit an online Gatekeeper
   check. Accepted trade-off; revisit by also notarizing/stapling the app if needed.
