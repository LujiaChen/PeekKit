#!/bin/bash
# Activate an already-copied, verified PeekKit bundle. No sudo or global security changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
APP=/Applications/PeekKit.app
ALLOW_QUARANTINE=0
RESIGN=0
CHECK_ONLY=0
PREPARE_ONLY=0
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'; else GREEN=; YELLOW=; RESET=; fi
info() { printf '%s%s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
fail() { warn "$*"; exit 1; }
usage() {
  cat <<'USAGE'
Usage: bash install-app.sh [--app /Applications/PeekKit.app] [options]
  --check-only                 Validate without changing files or registration
  --allow-quarantine-removal   Remove only this app's com.apple.quarantine attributes
  --resign                     Re-sign verified code inside-out, preserving entitlements
  --prepare-only               Validate/prepare only; skip registration and Quick Look reset
  --help                       Show this help

Copy PeekKit.app to Applications first. Verify the release download's SHA-256
before using this helper. It is ad-hoc signed, NOT Apple notarized. Removing
quarantine is an explicit trust decision for this app, not Apple approval.
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) [[ $# -ge 2 && -n "$2" ]] || fail '--app requires a path'; APP="$2"; shift 2 ;;
    --allow-quarantine-removal) ALLOW_QUARANTINE=1; shift ;;
    --resign) RESIGN=1; shift ;;
    --check-only) CHECK_ONLY=1; shift ;;
    --prepare-only) PREPARE_ONLY=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unknown argument: $1 (see --help)" ;;
  esac
done
[[ "$(/usr/bin/uname -s)" == Darwin && "$(/usr/bin/uname -m)" == arm64 ]] || fail 'Requires an Apple Silicon Mac.'
[[ "$APP" == /* && "$APP" == */PeekKit.app && -d "$APP" && ! -L "$APP" ]] || fail 'Choose an existing absolute path ending in /PeekKit.app.'
[[ "$(cd "$APP" && pwd -P)" == "$APP" ]] || fail 'App path must not contain symbolic links or relative components.'
[[ -f "$ROOT/Tools/verify-app.sh" && ! -L "$ROOT/Tools/verify-app.sh" ]] || fail 'Keep this helper with its Tools/verify-app.sh file.'
# Validate BEFORE touching quarantine or signatures; do not bless a damaged download.
/bin/bash "$ROOT/Tools/verify-app.sh" "$APP"
if [[ "$CHECK_ONLY" == 1 ]]; then info 'Check complete; no files or registrations changed.'; exit 0; fi
[[ -w "$APP" ]] || fail 'App is not writable. Copy it to a folder you own, or use a local source build. No automatic sudo is used.'
QUARANTINED=()
while IFS= read -r -d '' ITEM; do
  if /usr/bin/xattr -p com.apple.quarantine "$ITEM" >/dev/null 2>&1; then QUARANTINED+=("$ITEM"); fi
done < <(/usr/bin/find "$APP" -print0)
if [[ ${#QUARANTINED[@]} -gt 0 && "$ALLOW_QUARANTINE" != 1 ]]; then
  fail 'Quarantine found. After verifying/trusting the download, rerun with --allow-quarantine-removal. No files were changed.'
fi
if [[ "$RESIGN" == 1 ]]; then
  DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1)"
  [[ "$DETAILS" == *'Signature=adhoc'* ]] || fail 'Refusing to replace a certificate signature with ad-hoc signing. Use its signed distribution instructions.'
  while IFS= read -r PROCESS; do
    case "$PROCESS" in "$APP"/Contents/*) fail 'Close PeekKit and its Quick Look previews before re-signing, then try again.' ;; esac
  done < <(/bin/ps -axo comm=)
  info 'Re-signing the two extensions, then the app; preserving their signed entitlements.'
  for KIND in Folder Markdown; do
    /usr/bin/codesign --force --sign - --timestamp=none --preserve-metadata=identifier,entitlements,flags "$APP/Contents/PlugIns/PeekKit${KIND}Preview.appex"
  done
  /usr/bin/codesign --force --sign - --timestamp=none --preserve-metadata=identifier,entitlements,flags "$APP"
  /bin/bash "$ROOT/Tools/verify-app.sh" "$APP"
fi
# Read each attribute individually: retain Finder tags, provenance and all other xattrs.
if [[ ${#QUARANTINED[@]} -gt 0 ]]; then
  for ITEM in "${QUARANTINED[@]}"; do /usr/bin/xattr -d com.apple.quarantine "$ITEM"; done
fi
info "Prepared PeekKit; removed ${#QUARANTINED[@]} quarantine attribute(s)."
if [[ "$PREPARE_ONLY" == 1 ]]; then info 'Registration and Quick Look caches were left unchanged.'; exit 0; fi
for KIND in Folder Markdown; do
  /usr/bin/pluginkit -a "$APP/Contents/PlugIns/PeekKit${KIND}Preview.appex"
done
/usr/bin/qlmanage -r
/usr/bin/qlmanage -r cache
for ID in com.lukechen.peekkit.folder com.lukechen.peekkit.markdown; do
  /usr/bin/pluginkit -m -A -D -v -i "$ID"
done
info 'Preparation and registration commands completed. Close/reopen Finder Quick Look.'
warn 'Registration is not proof of activation. Keep one installed copy; remove old copies if the paths above include duplicates.'
warn 'Open PeekKit once, then enable PeekKit Folder and PeekKit Markdown in System Settings > General > Login Items & Extensions > Quick Look (location varies by macOS).'
warn 'Test a folder and a Markdown file with Space in Finder. This helper does not notarize the app or guarantee acceptance on every Mac.'
