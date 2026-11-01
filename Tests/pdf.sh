#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
REPORT="${1:-$ROOT/.build/test-results/PDF-Validation.json}"
mkdir -p "$(dirname "$REPORT")"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/peekkit-pdf.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
xcrun swiftc -O -swift-version 5 -module-cache-path "$TEMP/cache" -parse-as-library "$ROOT/Sources/FileBackedPDF.swift" "$ROOT/Sources/PDFContent.swift" "$ROOT/Sources/LocalFilePolicy.swift" "$ROOT/Sources/FolderAnalysis.swift" "$ROOT/Tests/PDFTests.swift" -o "$TEMP/tests"
"$TEMP/tests" "$TEMP/fixtures" "$REPORT"
