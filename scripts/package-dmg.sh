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
# Tuist names the product after the target (MirrorballSwift.app), so discover
# the exported bundle instead of assuming its filename.
APP="$(/usr/bin/find "$EXPORT_DIR" -maxdepth 1 -name '*.app' -print -quit)"
[[ -n "$APP" && -d "$APP" ]] || {
  echo "export failed: no .app found in $EXPORT_DIR" >&2
  ls -la "$EXPORT_DIR" >&2 || true
  exit 1
}
echo "exported app: $APP"
codesign --verify --deep --strict --verbose=2 "$APP"
# show the signing authority so a misconfigured identity is visible in the log
codesign --display --verbose=2 "$APP" 2>&1 | grep -iE 'Authority|TeamIdentifier' || true

# --- 5. build the DMG (app + Applications shortcut) ------------------------
# Use hdiutil, not create-dmg: create-dmg drives Finder over AppleScript to
# position icons, which needs a GUI login session and times out (AppleEvent
# -1712) on a headless CI runner, producing no image. hdiutil needs no GUI.
echo "==> build DMG (hdiutil)"
STAGING="$WORK/dmg"
mkdir -p "$STAGING"
# Ship a branded Mirrorball.app regardless of the build product name. Renaming
# the .app directory does not affect its code signature (the signature seals the
# bundle contents and Info.plist, not the directory name).
cp -R "$APP" "$STAGING/Mirrorball.app"
# the "drag to Applications" shortcut is just a symlink — no Finder needed
ln -s /Applications "$STAGING/Applications"
DMG="$REPO_ROOT/Mirrorball-$VERSION.dmg"
rm -f "$DMG"
hdiutil create \
  -volname "Mirrorball $VERSION" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG"
[[ -f "$DMG" ]] || { echo "hdiutil failed: no DMG produced" >&2; exit 1; }
# sign the DMG itself with the Developer ID identity
codesign --force --sign "Developer ID Application" --timestamp "$DMG"
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
