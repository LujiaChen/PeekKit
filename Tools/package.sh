#!/bin/bash
# A production ZIP is emitted only after Developer ID, notarization and Gatekeeper checks.
set -euo pipefail
APP="${1:?Usage: package.sh /path/PeekKit.app /new/output/directory}"
OUTPUT="${2:?Output directory required}"
: "${PEEKKIT_NOTARY_PROFILE:?Set an existing notarytool keychain profile; never store credentials in this repository}"
[[ ! -e "$OUTPUT" ]] || { echo 'Output directory already exists' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
[[ "$DETAILS" == *'Authority=Developer ID Application:'* && "$DETAILS" == *'runtime'* ]] || { echo 'Developer ID Application signing with hardened runtime is required' >&2; exit 1; }
mkdir -p "$OUTPUT"
ditto -c -k --norsrc --keepParent "$APP" "$OUTPUT/submission.zip"
xcrun notarytool submit "$OUTPUT/submission.zip" --keychain-profile "$PEEKKIT_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --norsrc --keepParent "$APP" "$OUTPUT/PeekKit-arm64-notarized.zip"
shasum -a 256 "$OUTPUT/PeekKit-arm64-notarized.zip" > "$OUTPUT/SHA256SUMS.txt"
echo 'Notarized ZIP created. Verify installation on a clean Mac before calling it production-ready.'
