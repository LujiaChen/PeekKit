#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
REPORT="${1:-$ROOT/.build/test-results/Registration-Validation.json}"
python3 - "$ROOT" "$REPORT" <<'PY'
import pathlib,plistlib,json,sys,re
root,report=map(pathlib.Path,sys.argv[1:]);read=lambda p:plistlib.loads((root/p).read_bytes())
folder=read('Resources/Folder-Info.plist');attrs=folder['NSExtension']['NSExtensionAttributes'];types=attrs['QLSupportedContentTypes']
required=['public.folder','org.7-zip.7-zip-archive','public.zip-archive','public.tar-archive','org.gnu.gnu-zip-archive','org.gnu.gnu-zip-tar-archive','public.bzip2-archive','public.tar-bzip2-archive']
checks={'declares_'+t:t in types for t in required}
app=read('Resources/App-Info.plist');version,build=app['CFBundleShortVersionString'],app['CFBundleVersion']
checks['consistentReleaseVersions']=bool(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',version) and re.fullmatch(r'[0-9]+',build)) and all(read('Resources/'+n+'-Info.plist')['CFBundleShortVersionString']==version and read('Resources/'+n+'-Info.plist')['CFBundleVersion']==build for n in ['App','Folder','Markdown'])
checks['nativeQuickLookController']=folder['NSExtension']['NSExtensionPointIdentifier']=='com.apple.quicklook.preview' and folder['NSExtension']['NSExtensionPrincipalClass']=='PeekKitFolderPreviewController' and attrs['QLIsDataBasedPreview'] is False
entitlements=read('Resources/Extension.entitlements');checks['sandboxWithoutNetwork']=entitlements.get('com.apple.security.app-sandbox') is True and entitlements.get('com.apple.security.network.client') is not True
for name,ok in checks.items():print(('PASS' if ok else 'FAIL'),name)
report.parent.mkdir(parents=True,exist_ok=True);report.write_text(json.dumps({'passed':all(checks.values()),'checks':checks},indent=2)+'\n')
assert all(checks.values()),checks
PY
