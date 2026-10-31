#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
REPORT="${1:-$ROOT/.build/test-results/Browser-Validation.json}"
mkdir -p "$(dirname "$REPORT")"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/peekkit-browser.XXXXXX")"
trap 'chmod -R u+rwX "$TEMP" 2>/dev/null || true; rm -rf "$TEMP"' EXIT
FILES=(); for F in "$ROOT"/Sources/*.swift; do [[ "$F" == */App.swift ]] || FILES+=("$F"); done
xcrun swiftc -O -swift-version 5 -module-cache-path "$TEMP/cache" -parse-as-library "${FILES[@]}" "$ROOT/Tests/BrowserTests.swift" -o "$TEMP/tests"
"$TEMP/tests" "$TEMP/fixtures" "$REPORT"
