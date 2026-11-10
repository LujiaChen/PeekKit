#!/bin/bash
# Credential-free packaging. This never claims Developer ID signing/notarization.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
APP="${1:?Usage: package-adhoc.sh /path/to/PeekKit.app /new/output/directory}"
OUTPUT="${2:?Output directory required}"
[[ ! -e "$OUTPUT" ]] || { echo 'Output directory already exists; refusing to overwrite it.' >&2; exit 1; }
[[ -z "$(/usr/bin/git -C "$ROOT" status --porcelain --untracked-files=normal)" ]] || { echo 'Commit source changes before packaging so the source ZIP matches the checkout.' >&2; exit 1; }
/bin/bash "$ROOT/Tools/verify-app.sh" "$APP"
for BUNDLE in "$APP" "$APP"/Contents/PlugIns/*.appex; do
  DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$BUNDLE" 2>&1)"
  [[ "$DETAILS" == *'Signature=adhoc'* ]] || { echo 'Expected ad-hoc signing for this packaging path.' >&2; exit 1; }
done
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
NAME="PeekKit-$VERSION-arm64-adhoc"
/bin/mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd -P)"
TEMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/peekkit-package.XXXXXX")"
TEMP="$(cd "$TEMP" && pwd -P)"
MOUNT=
cleanup() {
  if [[ -n "$MOUNT" ]]; then /usr/bin/hdiutil detach -quiet "$MOUNT" || true; fi
  /bin/rm -rf "$TEMP"
}
trap cleanup EXIT
STAGE="$TEMP/$NAME"
/bin/mkdir -p "$STAGE/Tools"
/usr/bin/ditto --norsrc "$APP" "$STAGE/PeekKit.app"
/bin/cp "$ROOT/install-app.sh" "$STAGE/"
/bin/cp "$ROOT/Tools/verify-app.sh" "$STAGE/Tools/"
/bin/cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/"
cat > "$STAGE/INSTALL.txt" <<EOF
PeekKit $VERSION — Apple Silicon, macOS 14+
Ad-hoc signed. NOT Developer ID signed or Apple notarized.

1. Verify the download with the SHA-256 manifest on its GitHub Release.
2. Close PeekKit/Quick Look. Keep an old app outside Applications temporarily.
3. Copy PeekKit.app to /Applications. Keep one installed copy.
4. Open Terminal in this folder (ZIP) or this mounted disk (DMG), then run:
   bash ./install-app.sh --allow-quarantine-removal
   This explicitly trusts this app and removes only its quarantine attributes.
   A valid signature is required first; it does not prove the publisher's identity.
5. Open PeekKit, enable both Quick Look extensions in System Settings, and test
   a folder and Markdown file with Space in Finder. Remove the old app after testing.

Re-sign only if needed: append --resign (close all PeekKit previews first).
Diagnose without changing anything: bash ./install-app.sh --check-only
The helper does not use sudo, disable global protections, or force-enable extensions.
If macOS still rejects the app, build from source rather than disabling protections.
Full instructions: https://github.com/LujiaChen/PeekKit/blob/v$VERSION/docs/INSTALL.md
EOF
/bin/bash "$ROOT/Tools/verify-app.sh" "$STAGE/PeekKit.app"
/usr/bin/ditto -c -k --norsrc --keepParent "$STAGE" "$OUTPUT/$NAME.zip"
/usr/bin/ditto -x -k "$OUTPUT/$NAME.zip" "$TEMP/roundtrip"
/bin/bash "$TEMP/roundtrip/$NAME/install-app.sh" --app "$TEMP/roundtrip/$NAME/PeekKit.app" --check-only
# A simple native disk image: no additional packaging dependencies or credentials.
/bin/ln -s /Applications "$STAGE/Applications"
/usr/bin/hdiutil create -quiet -volname "PeekKit $VERSION" -srcfolder "$STAGE" -format UDZO "$OUTPUT/$NAME.dmg"
/usr/bin/hdiutil verify "$OUTPUT/$NAME.dmg"
/bin/mkdir "$TEMP/mounted"
MOUNT="$TEMP/mounted"
/usr/bin/hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$OUTPUT/$NAME.dmg"
/bin/bash "$MOUNT/install-app.sh" --app "$MOUNT/PeekKit.app" --check-only
/usr/bin/hdiutil detach -quiet "$MOUNT"
MOUNT=
# Source archive includes scripts/notices and preserves executable bits.
/usr/bin/git -C "$ROOT" archive --format=zip --prefix="PeekKit-$VERSION/" HEAD -o "$OUTPUT/PeekKit-$VERSION-source.zip"
(
  cd "$OUTPUT"
  /usr/bin/shasum -a 256 "$NAME.zip" "$NAME.dmg" "PeekKit-$VERSION-source.zip" > SHA256SUMS.txt
  /usr/bin/shasum -a 256 -c SHA256SUMS.txt
)
echo "Packaged $NAME ZIP/DMG and source with SHA-256 checksums in $OUTPUT"
