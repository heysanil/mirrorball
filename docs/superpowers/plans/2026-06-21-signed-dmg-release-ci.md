# Signed-DMG Release CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub Actions workflow on Namespace macOS runners that builds, Developer ID-signs, notarizes, staples, and packages Mirrorball into a drag-install DMG (`Mirrorball.app` + an Applications folder shortcut), uploaded as a workflow artifact and attached to a GitHub Release on `v*` tags.

**Architecture:** A thin workflow (`.github/workflows/release.yml`) handles triggers, the Namespace runner, secrets→env, and artifact/Release upload. All build/sign/package logic lives in a committed, locally runnable script (`scripts/package-dmg.sh`) that does `tuist generate` → `xcodebuild archive` → `-exportArchive` (Developer ID) → `create-dmg` → `notarytool submit --wait` → `stapler staple`. Developer ID signing is applied at *export* time via `.github/ExportOptions.plist`, leaving `Project.swift` untouched.

**Tech Stack:** GitHub Actions, Namespace macOS runners (`nscloud-macos-tahoe-arm64-6x14`), Tuist, `xcodebuild`, `create-dmg` (Homebrew), `xcrun notarytool`/`stapler`, `security` keychain CLI, bash.

## Global Constraints

- Deployment/build target: **macOS 26 / Xcode 26 / Swift 6.2** — runner MUST be the Tahoe image (`nscloud-macos-tahoe-arm64-6x14`).
- **The secret never appears in `ssh`/process argv** — keep secrets in env and temp files; this plan adds signing secrets, all passed via env, never as CLI args that get logged.
- **Do NOT modify `Project.swift`** — Developer ID signing happens at export time. Keep `CODE_SIGN_IDENTITY = "-"`, hardened runtime, and the non-sandbox entitlement intact.
- **No AI references in commit messages.** Conventional commits, imperative subject, explain *why* in the body.
- Bundle id: `co.sanil.mirrorball`. App product name: `Mirrorball.app`. Scheme/workspace: `MirrorballSwift`.
- Notary credential: App Store Connect **API key** (`.p8`).
- Secret env var names (exact, used by script + workflow + README):
  `DEVELOPER_ID_APP_CERT_P12_BASE64`, `DEVELOPER_ID_APP_CERT_PASSWORD`, `KEYCHAIN_PASSWORD`,
  `APPLE_TEAM_ID`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`, `NOTARY_API_KEY_P8_BASE64`.

---

### Task 1: Packaging engine — `ExportOptions.plist` + `package-dmg.sh`

**Files:**
- Create: `.github/ExportOptions.plist`
- Create: `scripts/package-dmg.sh`
- Modify: `.gitignore` (append `*.dmg`)

**Interfaces:**
- Produces: an executable `scripts/package-dmg.sh` accepting `--version <v>` and `--no-notarize`, reading the seven secret env vars above, writing `Mirrorball-<version>.dmg` to the repo root, and (when `$GITHUB_OUTPUT` is set) appending `dmg=<path>` and `version=<v>` to it. Task 2 (workflow) consumes those outputs.

- [ ] **Step 1: Create the Developer ID export options**

Create `.github/ExportOptions.plist` (the `__TEAM_ID__` token is replaced at runtime by the script):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>teamID</key>
	<string>__TEAM_ID__</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
</dict>
</plist>
```

- [ ] **Step 2: Write the packaging script**

Create `scripts/package-dmg.sh`:

```bash
#!/usr/bin/env bash
#
# package-dmg.sh — build, Developer ID-sign, notarize, staple, and package
# Mirrorball into a drag-install DMG (Mirrorball.app + an Applications shortcut).
#
# Runs identically in CI and locally. Reads signing secrets from the environment
# (see README "Building & releasing"). Use --no-notarize to skip the Apple
# round-trip for a local smoke test.
#
# Usage: scripts/package-dmg.sh [--version X.Y.Z] [--no-notarize]

set -euo pipefail

# --- args -------------------------------------------------------------------
VERSION=""
NOTARIZE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
    --no-notarize) NOTARIZE=0; shift ;;
    -h|--help) grep '^#' "$0" | cut -c3-; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ -z "$VERSION" ]]; then
  VERSION="$(grep -m1 'MARKETING_VERSION' Project.swift | sed -E 's/.*"([0-9.]+)".*/\1/')"
fi
echo "==> Packaging Mirrorball $VERSION (notarize=$NOTARIZE)"

WORK="$(mktemp -d)"
KEYCHAIN_PATH="$WORK/mirrorball-signing.keychain-db"
cleanup() {
  security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- 1. generate the Xcode project (it is gitignored) ----------------------
echo "==> tuist generate"
tuist generate --no-open

# --- 2. import the Developer ID cert into a throwaway keychain --------------
: "${DEVELOPER_ID_APP_CERT_P12_BASE64:?missing DEVELOPER_ID_APP_CERT_P12_BASE64}"
: "${DEVELOPER_ID_APP_CERT_PASSWORD:?missing DEVELOPER_ID_APP_CERT_PASSWORD}"
: "${KEYCHAIN_PASSWORD:?missing KEYCHAIN_PASSWORD}"
echo "==> import signing certificate"
echo "$DEVELOPER_ID_APP_CERT_P12_BASE64" | base64 --decode > "$WORK/cert.p12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$WORK/cert.p12" -P "$DEVELOPER_ID_APP_CERT_PASSWORD" \
  -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
# allow codesign/xcodebuild to use the key without an interactive prompt
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
# make the temp keychain searchable alongside the existing defaults
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN_PATH" \
  $(security list-keychains -d user | sed 's/"//g')

# --- 3. archive -------------------------------------------------------------
echo "==> xcodebuild archive"
ARCHIVE="$WORK/Mirrorball.xcarchive"
xcodebuild archive \
  -workspace MirrorballSwift.xcworkspace \
  -scheme MirrorballSwift \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

# --- 4. export with Developer ID --------------------------------------------
echo "==> export (Developer ID)"
: "${APPLE_TEAM_ID:?missing APPLE_TEAM_ID}"
cp ".github/ExportOptions.plist" "$WORK/ExportOptions.plist"
/usr/libexec/PlistBuddy -c "Set :teamID $APPLE_TEAM_ID" "$WORK/ExportOptions.plist"
EXPORT_DIR="$WORK/export"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$WORK/ExportOptions.plist"
APP="$EXPORT_DIR/Mirrorball.app"
[[ -d "$APP" ]] || { echo "export failed: $APP not found" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"

# --- 5. build the DMG (app icon + Applications drop link) -------------------
echo "==> create-dmg"
STAGING="$WORK/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
DMG="$REPO_ROOT/Mirrorball-$VERSION.dmg"
rm -f "$DMG"
# create-dmg can exit non-zero on cosmetic Finder-styling hiccups while still
# producing a valid image, so tolerate its exit code and assert the file exists.
create-dmg \
  --volname "Mirrorball $VERSION" \
  --window-size 540 380 \
  --icon-size 110 \
  --icon "Mirrorball.app" 140 190 \
  --app-drop-link 400 190 \
  --codesign "Developer ID Application" \
  --no-internet-enable \
  "$DMG" "$STAGING" || true
[[ -f "$DMG" ]] || { echo "create-dmg failed: no DMG produced" >&2; exit 1; }
codesign --verify --verbose=2 "$DMG"

# --- 6. notarize + staple ---------------------------------------------------
if [[ "$NOTARIZE" == 1 ]]; then
  : "${NOTARY_API_KEY_ID:?missing NOTARY_API_KEY_ID}"
  : "${NOTARY_API_ISSUER_ID:?missing NOTARY_API_ISSUER_ID}"
  : "${NOTARY_API_KEY_P8_BASE64:?missing NOTARY_API_KEY_P8_BASE64}"
  echo "==> notarize"
  echo "$NOTARY_API_KEY_P8_BASE64" | base64 --decode > "$WORK/AuthKey.p8"
  xcrun notarytool submit "$DMG" \
    --key "$WORK/AuthKey.p8" \
    --key-id "$NOTARY_API_KEY_ID" \
    --issuer "$NOTARY_API_ISSUER_ID" \
    --wait
  echo "==> staple"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
else
  echo "==> skipping notarization (--no-notarize)"
fi

# --- 7. emit outputs --------------------------------------------------------
echo "==> done: $DMG"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "dmg=$DMG"
    echo "version=$VERSION"
  } >> "$GITHUB_OUTPUT"
fi
```

- [ ] **Step 3: Make the script executable and ignore built DMGs**

Run:
```bash
chmod +x scripts/package-dmg.sh
grep -qxF '*.dmg' .gitignore || printf '\n# Release artifacts\n*.dmg\n' >> .gitignore
```

- [ ] **Step 4: Lint the script (syntax + shellcheck)**

Run:
```bash
bash -n scripts/package-dmg.sh
brew install shellcheck >/dev/null 2>&1 || true
shellcheck scripts/package-dmg.sh
```
Expected: `bash -n` prints nothing (exit 0); `shellcheck` reports no errors (the one `SC2046` on the `list-keychains` line is suppressed by the inline `# shellcheck disable` comment).

- [ ] **Step 5: Verify the `--help` path works without secrets**

Run:
```bash
scripts/package-dmg.sh --help
```
Expected: prints the header comment block (usage), exits 0, touches nothing.

- [ ] **Step 6: (Optional, needs your certs) local smoke test without notarization**

Only if you have the Developer ID cert handy locally. Export the four signing vars (`DEVELOPER_ID_APP_CERT_P12_BASE64`, `DEVELOPER_ID_APP_CERT_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_TEAM_ID`) and run:
```bash
scripts/package-dmg.sh --version 0.0.0-smoke --no-notarize
```
Expected: produces `Mirrorball-0.0.0-smoke.dmg`; `codesign --verify` passes. Then:
```bash
hdiutil attach Mirrorball-0.0.0-smoke.dmg -nobrowse -mountpoint /tmp/mb && \
  ls -la /tmp/mb && hdiutil detach /tmp/mb
```
Expected: the mounted volume shows `Mirrorball.app` and an `Applications` symlink. Clean up: `rm Mirrorball-0.0.0-smoke.dmg`.

- [ ] **Step 7: Commit**

```bash
git add .github/ExportOptions.plist scripts/package-dmg.sh .gitignore
git commit -m "feat(ci): add Developer ID build + notarize + DMG packaging script

Locally-runnable script that generates the Tuist project, archives and
exports the app with the Developer ID identity, builds a drag-install DMG
(app + Applications shortcut), then notarizes and staples it. Signing is
applied at export time so Project.swift is untouched."
```

---

### Task 2: GitHub Actions workflow — `release.yml`

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `scripts/package-dmg.sh` from Task 1 and its `dmg`/`version` step outputs.
- Produces: a `build-dmg` job on `nscloud-macos-tahoe-arm64-6x14` that runs on `v*` tags and manual dispatch, uploads the DMG artifact always, and attaches it to a Release on tag builds.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release DMG

on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      version:
        description: "Version (no leading v); defaults to MARKETING_VERSION in Project.swift"
        required: false
        default: ""

permissions:
  contents: write   # create the Release and upload the DMG asset

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build-dmg:
    runs-on: nscloud-macos-tahoe-arm64-6x14
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 26
        run: |
          if [[ -d /Applications/Xcode_26.app ]]; then
            sudo xcode-select -s /Applications/Xcode_26.app/Contents/Developer
          fi
          sudo xcodebuild -runFirstLaunch || true
          xcodebuild -version

      - name: Install Tuist & create-dmg
        run: brew install tuist create-dmg

      - name: Resolve version
        id: ver
        run: |
          if [[ "${GITHUB_REF}" == refs/tags/v* ]]; then
            V="${GITHUB_REF#refs/tags/v}"
          elif [[ -n "${{ github.event.inputs.version }}" ]]; then
            V="${{ github.event.inputs.version }}"
          else
            V="$(grep -m1 'MARKETING_VERSION' Project.swift | sed -E 's/.*"([0-9.]+)".*/\1/')"
          fi
          echo "version=$V" >> "$GITHUB_OUTPUT"
          echo "Resolved version: $V"

      - name: Build, sign, notarize, package
        id: package
        env:
          DEVELOPER_ID_APP_CERT_P12_BASE64: ${{ secrets.DEVELOPER_ID_APP_CERT_P12_BASE64 }}
          DEVELOPER_ID_APP_CERT_PASSWORD: ${{ secrets.DEVELOPER_ID_APP_CERT_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          NOTARY_API_KEY_ID: ${{ secrets.NOTARY_API_KEY_ID }}
          NOTARY_API_ISSUER_ID: ${{ secrets.NOTARY_API_ISSUER_ID }}
          NOTARY_API_KEY_P8_BASE64: ${{ secrets.NOTARY_API_KEY_P8_BASE64 }}
        run: ./scripts/package-dmg.sh --version "${{ steps.ver.outputs.version }}"

      - name: Upload workflow artifact
        uses: actions/upload-artifact@v4
        with:
          name: Mirrorball-${{ steps.ver.outputs.version }}
          path: ${{ steps.package.outputs.dmg }}
          if-no-files-found: error

      - name: Attach DMG to GitHub Release
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: ${{ steps.package.outputs.dmg }}
          fail_on_unmatched_files: true
```

- [ ] **Step 2: Validate the workflow YAML**

Run:
```bash
brew install actionlint >/dev/null 2>&1 || true
actionlint .github/workflows/release.yml
```
Expected: no output / exit 0. (If `actionlint` is unavailable, fall back to a parse check: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml'))"` — expected: no output.)

- [ ] **Step 3: Confirm secret names match the script**

Run:
```bash
diff <(grep -oE '[A-Z_]+:' .github/workflows/release.yml | grep -E 'CERT|KEYCHAIN|TEAM|NOTARY' | tr -d ':' | sort -u) \
     <(grep -oE '\$\{[A-Z_]+' scripts/package-dmg.sh | tr -d '${' | grep -E 'CERT|KEYCHAIN|TEAM|NOTARY' | sort -u)
```
Expected: no differences — the env var names referenced in the workflow exactly match those the script reads.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat(ci): add Namespace macOS workflow to build and release signed DMGs

Runs on nscloud-macos-tahoe-arm64-6x14 for v* tags and manual dispatch,
calls scripts/package-dmg.sh with signing secrets from env, uploads the
DMG as an artifact, and attaches it to the matching Release on tags."
```

---

### Task 3: Document the release process in the README

**Files:**
- Modify: `README.md` (append a "Building & releasing" section near the end)

**Interfaces:**
- Consumes: the secret names from Task 1 and the trigger behavior from Task 2. No code depends on this task.

- [ ] **Step 1: Read the README tail to find the insertion point**

Run:
```bash
tail -n 30 README.md
```
Note the last section so the new one is appended cleanly (after the final existing section, before any license footer if present).

- [ ] **Step 2: Append the release section**

Add this section to `README.md` (place it after the last content section; if a License section is last, insert immediately before it):

```markdown
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
```

- [ ] **Step 3: Verify the secret table matches the script**

Run:
```bash
for v in DEVELOPER_ID_APP_CERT_P12_BASE64 DEVELOPER_ID_APP_CERT_PASSWORD KEYCHAIN_PASSWORD APPLE_TEAM_ID NOTARY_API_KEY_ID NOTARY_API_ISSUER_ID NOTARY_API_KEY_P8_BASE64; do
  grep -q "$v" README.md && grep -q "$v" scripts/package-dmg.sh || echo "MISMATCH: $v"
done
```
Expected: no `MISMATCH` lines printed.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document the signed-DMG release workflow and required secrets"
```

---

### Task 4: Acceptance (manual — requires secrets + Namespace configured)

**Files:** none (operational verification).

This task cannot run in CI's own test harness; it is the real end-to-end gate and
requires you to have completed the one-time Namespace + Apple setup and added all
seven secrets.

- [ ] **Step 1: Push a throwaway test tag**

```bash
git push origin ci/signed-dmg-release        # ensure the workflow file is on the remote
git tag v0.0.1-test && git push origin v0.0.1-test
```

- [ ] **Step 2: Watch the run**

```bash
gh run watch "$(gh run list --workflow 'Release DMG' --limit 1 --json databaseId -q '.[0].databaseId')"
```
Expected: the `build-dmg` job succeeds; the **Select Xcode 26** step logs `Xcode 26.x` (if it logs an older Xcode, the Tahoe image lacks 26 — stop and adjust the select step).

- [ ] **Step 3: Validate the produced DMG**

Download the artifact (or the Release asset) and run:
```bash
xcrun stapler validate Mirrorball-0.0.1-test.dmg
spctl -a -vv -t install Mirrorball-0.0.1-test.dmg
hdiutil attach Mirrorball-0.0.1-test.dmg -nobrowse -mountpoint /tmp/mb
spctl -a -vv /tmp/mb/Mirrorball.app
hdiutil detach /tmp/mb
```
Expected: `stapler validate` → "The validate action worked!"; `spctl` → `accepted` / `source=Notarized Developer ID`; the mounted volume shows `Mirrorball.app` next to an `Applications` shortcut.

- [ ] **Step 4: Tear down the test release**

```bash
gh release delete v0.0.1-test --cleanup-tag --yes
git tag -d v0.0.1-test
```

---

## Self-Review

**Spec coverage:**
- Trigger (`v*` tag + manual dispatch) → Task 2 workflow `on:` block. ✓
- Runner `nscloud-macos-tahoe-arm64-6x14` → Task 2. ✓
- Developer ID sign → notarize → staple → Task 1 script steps 2–6. ✓
- App Store Connect API key notary cred → Task 1 step 6 + secrets. ✓
- DMG = app + Applications shortcut → Task 1 step 5 (`--app-drop-link`). ✓
- Output: always artifact + Release on tag → Task 2 upload-artifact + conditional action-gh-release. ✓
- No `Project.swift` change; export-time signing → Task 1 ExportOptions + Global Constraints. ✓
- README "Building & releasing" + secrets table → Task 3. ✓
- Verification (`stapler validate`/`spctl`, `--no-notarize` smoke) → Task 1 step 6, Task 4. ✓
- `Project.swift` `MARKETING_VERSION` version derivation → Task 1 (fallback grep) + Task 2 (ver step). ✓

**Placeholder scan:** `__TEAM_ID__` is an intentional runtime-substituted token (replaced via PlistBuddy in Task 1 step 2), not a plan placeholder. No TODO/TBD/"add error handling" present. ✓

**Type/name consistency:** the seven secret env var names are identical across Global Constraints, Task 1 script, Task 2 workflow `env:`, and Task 3 README table; the script's `$GITHUB_OUTPUT` keys (`dmg`, `version`) match Task 2's `steps.package.outputs.dmg` / `steps.ver.outputs.version` references; DMG filename `Mirrorball-<version>.dmg` is consistent across script, artifact path, and acceptance checks. ✓

**Risks carried from the spec:** Xcode 26 presence on the Tahoe image (Task 4 step 2 explicitly checks the logged version); Namespace tenant connection (Task 3 one-time setup); `create-dmg` cosmetic non-zero exit (tolerated in Task 1 step 2 with a file-existence assertion).
```
