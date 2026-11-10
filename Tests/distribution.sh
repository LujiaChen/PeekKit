#!/bin/bash
# All mutations target a temporary copy; never register it or reset the user's Quick Look.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
python3 "$ROOT/Tests/distribution.py" "${1:-$ROOT/.build/PeekKit.app}"
