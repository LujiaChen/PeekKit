#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
REPORT="${1:-$ROOT/.build/test-results/Archive-Validation.json}"
mkdir -p "$(dirname "$REPORT")"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/peekkit-archive.XXXXXX")"
trap 'chmod -R u+rwX "$TEMP" 2>/dev/null || true; rm -rf "$TEMP"' EXIT
python3 - "$TEMP" <<'PY'
import io,tarfile,zipfile,pathlib,sys,subprocess
r=pathlib.Path(sys.argv[1])
for suffix,mode in [('tar','w'),('tar.gz','w:gz'),('tar.bz2','w:bz2'),('tar.xz','w:xz')]:
 with tarfile.open(r/('valid.'+suffix),mode) as a:
  t=tarfile.TarInfo('nested/你好.txt');t.size=5;a.addfile(t,io.BytesIO(b'hello'))
with zipfile.ZipFile(r/'valid.zip','w',compression=zipfile.ZIP_DEFLATED) as a:a.writestr('nested/你好.txt',b'hello')
with zipfile.ZipFile(r/'empty.zip','w'):pass
with zipfile.ZipFile(r/'absolute.zip','w') as a:a.writestr('/tmp/evil',b'x')
with zipfile.ZipFile(r/'duplicate.zip','w') as a:a.writestr('x',b'x');a.writestr('x',b'y')
for name,path,kind,size in [('traversal','../evil',tarfile.REGTYPE,1),('symlink','link',tarfile.SYMTYPE,0),('hardlink','link',tarfile.LNKTYPE,0),('fifo','pipe',tarfile.FIFOTYPE,0),('deep','/'.join(['d']*65),tarfile.DIRTYPE,0),('huge','huge',tarfile.REGTYPE,33*1024*1024)]:
 with tarfile.open(r/(name+'.tar'),'w') as a:
  t=tarfile.TarInfo(path);t.type=kind;t.size=size;t.linkname='target'
  if name=='huge':a.fileobj.write(t.tobuf())
  else:a.addfile(t,io.BytesIO(b'x') if size else None)
with tarfile.open(r/'many.tar','w') as a:
 for i in range(20001):a.addfile(tarfile.TarInfo(str(i)))
with zipfile.ZipFile(r/'bomb.zip','w',compression=zipfile.ZIP_DEFLATED) as a:a.writestr('bomb',b'0'*(33*1024*1024))
(r/'corrupt.zip').write_bytes(b'PKxxjunk')
b=(r/'valid.zip').read_bytes();(r/'truncated.zip').write_bytes(b[:len(b)//2])
with (r/'oversize.zip').open('wb') as f:f.truncate(64*1024*1024+1)
(r/'secret.txt').write_text('secret');subprocess.run(['/usr/bin/zip','-q','-P','fixture-password',str(r/'encrypted.zip'),'secret.txt'],cwd=r,check=True)
PY
xcrun swiftc -O -swift-version 5 -I "$ROOT/Vendor/LibArchive" -module-cache-path "$TEMP/cache" -parse-as-library "$ROOT/Sources/ArchiveReader.swift" "$ROOT/Sources/FolderAnalysis.swift" "$ROOT/Sources/LocalFilePolicy.swift" "$ROOT/Tests/ArchiveTests.swift" -o "$TEMP/tests"
"$TEMP/tests" "$TEMP" "$REPORT"
