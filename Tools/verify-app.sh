#!/bin/bash
# Structural/signature validation, not a Gatekeeper or notarization assessment.
set -euo pipefail
APP="${1:?Usage: verify-app.sh /path/to/PeekKit.app}"
fail() { echo "Invalid PeekKit bundle: $*" >&2; exit 1; }
[[ -d "$APP" && ! -L "$APP" ]] || fail 'app is missing or is a symbolic link'
[[ -z "$(/usr/bin/find "$APP" -type l -print -quit)" ]] || fail 'unexpected symbolic link inside app'
APP="$(cd "$APP" && pwd -P)"
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
[[ "$(plist "$APP" CFBundleIdentifier)" == com.lukechen.peekkit ]] || fail 'wrong application identifier'
VERSION="$(plist "$APP" CFBundleShortVersionString)"
BUILD="$(plist "$APP" CFBundleVersion)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[0-9]+$ ]] || fail 'invalid version'
[[ "$(plist "$APP" CFBundleExecutable)" == PeekKit ]] || fail 'unexpected app executable'
# file is a system tool; lipo is a developer-tool shim on Macs without Xcode/CLT.
[[ "$(/usr/bin/file -b "$APP/Contents/MacOS/PeekKit")" == 'Mach-O 64-bit executable arm64' ]] || fail 'expected arm64 executable'
/usr/bin/codesign --verify --deep --strict "$APP"
TEMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/peekkit-verify.XXXXXX")"
trap '/bin/rm -rf "$TEMP"' EXIT
shopt -s nullglob
EXTENSIONS=("$APP"/Contents/PlugIns/*)
[[ ${#EXTENSIONS[@]} == 2 ]] || fail 'expected exactly two extensions'
for KIND in Folder Markdown; do
  EXT="$APP/Contents/PlugIns/PeekKit${KIND}Preview.appex"
  LOWER="$(echo "$KIND" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  [[ -d "$EXT" ]] || fail "missing $KIND extension"
  [[ "$(plist "$EXT" CFBundleIdentifier)" == "com.lukechen.peekkit.$LOWER" ]] || fail 'wrong extension identifier'
  [[ "$(plist "$EXT" CFBundleShortVersionString)" == "$VERSION" && "$(plist "$EXT" CFBundleVersion)" == "$BUILD" ]] || fail 'extension version mismatch'
  [[ "$(plist "$EXT" CFBundleExecutable)" == "PeekKit${KIND}Preview" ]] || fail 'unexpected extension executable'
  [[ "$(plist "$EXT" NSExtension:NSExtensionPointIdentifier)" == com.apple.quicklook.preview ]] || fail 'wrong extension point'
  [[ "$(/usr/bin/file -b "$EXT/Contents/MacOS/PeekKit${KIND}Preview")" == 'Mach-O 64-bit executable arm64' ]] || fail 'expected arm64 extension'
  /usr/bin/codesign --verify --strict "$EXT"
  # New codesign defaults to a human-readable representation; older macOS uses XML.
  if ! /usr/bin/codesign -d --entitlements - --xml "$EXT" > "$TEMP/entitlements.plist" 2> "$TEMP/codesign.log"; then
    /usr/bin/codesign -d --entitlements :- "$EXT" > "$TEMP/entitlements.plist" 2> "$TEMP/codesign.log"
  fi
  for KEY in com.apple.security.app-sandbox com.apple.security.files.user-selected.read-only; do
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$TEMP/entitlements.plist")" == true ]] || fail "missing $KEY"
  done
  for KEY in com.apple.security.network.client com.apple.security.network.server com.apple.security.files.user-selected.read-write; do
    VALUE="$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$TEMP/entitlements.plist" 2>/dev/null || true)"
    [[ "$VALUE" != true ]] || fail "unexpected entitlement $KEY"
  done
done
echo "Verified PeekKit $VERSION (build $BUILD), arm64, main app and both sandboxed Quick Look extensions."
