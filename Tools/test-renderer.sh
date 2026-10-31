#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
APP="${1:-$ROOT/.build/PeekKit.app}"
REPORT="${2:-$ROOT/.build/test-results/Renderer-Validation.json}"
mkdir -p "$(dirname "$REPORT")"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/peekkit-renderer.XXXXXX")"
trap 'rm -rf "$TEMP"' EXIT
python3 - "$APP" "$TEMP" "$REPORT" <<'PY'
import pathlib,subprocess,json,sys
app,tmp,report=map(pathlib.Path,sys.argv[1:])
f=tmp/'renderer.json'
subprocess.run([str(app/'Contents/MacOS/PeekKit'),'--self-test',str(f)],check=True,timeout=90)
data=json.loads(f.read_text());assert data.get('passed'),data
report.write_text(json.dumps(data,indent=2)+'\n')
print('Renderer checks:',sum(v is True for k,v in data.items() if k!='passed'),'passed')
PY
