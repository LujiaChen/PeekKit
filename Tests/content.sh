#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
APP="${1:-$ROOT/.build/PeekKit.app}"
REPORT="${2:-$ROOT/.build/test-results/Content-Validation.json}"
mkdir -p "$(dirname "$REPORT")"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/peekkit-content.XXXXXX")"
trap 'chmod -R u+rwX "$TEMP" 2>/dev/null || true; rm -rf "$TEMP"' EXIT
xcrun swiftc -O -swift-version 5 -module-cache-path "$TEMP/cache" -parse-as-library "$ROOT/Sources/FolderAnalysis.swift" "$ROOT/Sources/LocalFilePolicy.swift" "$ROOT/Sources/AnalysisExport.swift" "$ROOT/Sources/MarkdownDocument.swift" "$ROOT/Tests/ContentTests.swift" -o "$TEMP/tests"
"$TEMP/tests" "$TEMP/fixtures" "$APP" "$REPORT"
