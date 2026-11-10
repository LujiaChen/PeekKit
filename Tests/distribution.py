"""Real macOS codesign/xattr regressions, isolated from the installed app/Finder."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(sys.argv[1]).resolve()
CHECKS = {}


def command(*args, ok=True):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    if ok and result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result


def check(name, value):
    CHECKS[name] = bool(value)
    print(('PASS' if value else 'FAIL'), name, flush=True)


def helper(app, *args, ok=True):
    return command('/bin/bash', ROOT / 'install-app.sh', '--app', app, *args, ok=ok)


def digest(app):
    return {str(p.relative_to(app)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in app.rglob('*') if p.is_file()}


def entitlements(ext):
    result = command('/usr/bin/codesign', '-d', '--entitlements', '-', '--xml', ext, ok=False)
    if result.returncode:
        result = command('/usr/bin/codesign', '-d', '--entitlements', ':-', ext)
    return plistlib.loads(result.stdout.encode())


def resign(app, ext=None, ent=None):
    if ext:
        args = ['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none']
        if ent:
            args += ['--entitlements', ent]
        else:
            args += ['--preserve-metadata=identifier,entitlements,flags']
        command(*args, ext)
    command('/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none', app)


with tempfile.TemporaryDirectory(prefix='PeekKit distribution tests ') as tmp:
    base = Path(tmp).resolve()
    app = base / 'Copy with spaces' / 'PeekKit.app'

    def fresh():
        if app.exists():
            shutil.rmtree(app)
        app.parent.mkdir(exist_ok=True)
        command('/usr/bin/ditto', '--norsrc', SOURCE, app)
        return app

    command('/bin/bash', ROOT / 'Tools/verify-app.sh', SOURCE)
    check('validBuiltBundle', True)
    fresh()
    before = digest(app)
    check('checkOnlyDoesNotModifyCode', helper(app, '--check-only').returncode == 0 and before == digest(app))
    check('doesNotRequireDeveloperTools', command('/usr/bin/env', 'DEVELOPER_DIR=/nonexistent', '/bin/bash', ROOT / 'install-app.sh', '--app', app, '--check-only').returncode == 0)
    check('unknownOptionRejected', helper(app, '--unknown', ok=False).returncode != 0)
    check('missingBundleRejected', helper(base / 'Missing.app', '--check-only', ok=False).returncode != 0)
    command('/usr/bin/xattr', '-w', 'com.apple.quarantine', '0083;00000000;PeekKitTest;', app)
    command('/usr/bin/xattr', '-w', 'org.peekkit.test', 'preserve me', app)
    nested = app / 'Contents/PlugIns/PeekKitFolderPreview.appex'
    command('/usr/bin/xattr', '-w', 'com.apple.quarantine', '0083;00000000;PeekKitTest;', nested)
    check('checkOnlyDoesNotRemoveQuarantine', helper(app, '--check-only').returncode == 0 and
          command('/usr/bin/xattr', '-p', 'com.apple.quarantine', app).returncode == 0)
    check('requiresExplicitTrustEvenWithResign', helper(app, '--prepare-only', '--resign', ok=False).returncode != 0 and
          digest(app) == before and command('/usr/bin/xattr', '-p', 'com.apple.quarantine', app).returncode == 0)
    expected = {k: entitlements(app / f'Contents/PlugIns/PeekKit{k}Preview.appex') for k in ('Folder', 'Markdown')}
    helper(app, '--prepare-only', '--allow-quarantine-removal', '--resign')
    check('explicitQuarantineRemovalIsRecursive', all(command('/usr/bin/xattr', '-p', 'com.apple.quarantine', p, ok=False).returncode != 0 for p in (app, nested)))
    check('unrelatedExtendedAttributesPreserved', command('/usr/bin/xattr', '-p', 'org.peekkit.test', app).stdout.strip() == 'preserve me')
    check('resigningPreservesBothEntitlements', all(entitlements(app / f'Contents/PlugIns/PeekKit{k}Preview.appex') == expected[k] for k in expected))
    check('resignedBundleRemainsValid', command('/bin/bash', ROOT / 'Tools/verify-app.sh', app).returncode == 0)
    check('preparationIsIdempotent', helper(app, '--prepare-only', '--allow-quarantine-removal').returncode == 0)

    fresh()
    link = base / 'Linked' / 'PeekKit.app'
    link.parent.mkdir()
    link.symlink_to(app, target_is_directory=True)
    check('symlinkAppRejected', helper(link, '--check-only', ok=False).returncode != 0)
    (app / 'Contents/Resources/escape').symlink_to(base)
    check('symlinkInsideBundleRejected', helper(app, '--check-only', ok=False).returncode != 0)
    fresh()
    (app / 'Contents/Resources/Welcome.md').write_text('tampered test')
    command('/usr/bin/xattr', '-w', 'com.apple.quarantine', '0083;00000000;PeekKitTest;', app)
    check('tamperedBundleNotBlessed', helper(app, '--prepare-only', '--allow-quarantine-removal', '--resign', ok=False).returncode != 0 and
          command('/usr/bin/xattr', '-p', 'com.apple.quarantine', app).returncode == 0)
    fresh()
    ext = app / 'Contents/PlugIns/PeekKitFolderPreview.appex'
    info = ext / 'Contents/Info.plist'
    data = plistlib.loads(info.read_bytes())
    data['CFBundleVersion'] = '99999'
    info.write_bytes(plistlib.dumps(data))
    resign(app, ext)
    check('signedVersionMismatchRejected', helper(app, '--check-only', ok=False).returncode != 0)
    fresh()
    bad_ent = base / 'network.plist'
    bad_ent.write_bytes(plistlib.dumps({**expected['Folder'], 'com.apple.security.network.client': True}))
    resign(app, ext, bad_ent)
    check('networkEntitlementRejected', helper(app, '--check-only', ok=False).returncode != 0)
    fresh()
    shutil.rmtree(app / 'Contents/PlugIns/PeekKitMarkdownPreview.appex')
    resign(app)
    check('missingExtensionRejected', helper(app, '--check-only', ok=False).returncode != 0)
    fresh()
    command('/usr/bin/ditto', ext, app / 'Contents/PlugIns/Unexpected.appex')
    resign(app)
    check('extraExtensionRejected', helper(app, '--check-only', ok=False).returncode != 0)

report = ROOT / '.build/test-results/Distribution-Validation.json'
report.parent.mkdir(parents=True, exist_ok=True)
report.write_text(json.dumps({'passed': all(CHECKS.values()), 'checks': CHECKS}, indent=2) + '\n')
assert all(CHECKS.values()), CHECKS
print(f'{len(CHECKS)}/{len(CHECKS)} distribution checks passed')
