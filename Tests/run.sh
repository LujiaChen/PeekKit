#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
REPORT="${1:-$SOURCE_DIR/.build/test-results/Analysis-Validation.json}"
mkdir -p "$(dirname "$REPORT")"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/peekkit-analysis.XXXXXX")"
trap 'chmod -R u+rwX "$TEST_DIR" 2>/dev/null || true; rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -O -swift-version 5 -module-cache-path "$TEST_DIR/cache" -parse-as-library "$SOURCE_DIR/Sources/FolderAnalysis.swift" "$SOURCE_DIR/Sources/FolderAnalysisModel.swift" "$SOURCE_DIR/Tests/FolderAnalysisTests.swift" -o "$TEST_DIR/tests"
"$TEST_DIR/tests" "$TEST_DIR/fixtures" "$REPORT"
echo "Report: $REPORT"
