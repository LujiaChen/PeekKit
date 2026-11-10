# Testing and verification

## Version 1.2 suites

```sh
./Tests/run.sh
./Tests/browser.sh
./build.sh
./Tests/content.sh
./Tools/test-renderer.sh
```

All scripts exit nonzero on a failing check and retain JSON reports in .build/test-results. Synthetic fixtures are removed by the runners. Renderer checks require a macOS graphical session. New validation and benchmark boundaries are in [UPGRADE-1.2.md](UPGRADE-1.2.md); 1.1 results below are historical.

## Reproduce

```sh
./Tests/run.sh
```

This compiles an optimized standalone runner, creates temporary fixtures, writes `.build/test-results/Analysis-Validation.json`, and removes the temporary fixtures/cache afterward. An optional first argument changes the report path.

After building, renderer checks can be run with:

```sh
.build/PeekKit.app/Contents/MacOS/PeekKit --self-test /absolute/path/to/a/test-directory/Renderer-Validation.json
```

Create the report directory first. This UI/WebKit test creates fixtures beside its report and requires a logged-in macOS graphical session. Keep it away from personal folders; remove the temporary test directory after reviewing results.

Existing diagnostic modes:

```sh
.build/PeekKit.app/Contents/MacOS/PeekKit --preview /absolute/path/to/folder
.build/PeekKit.app/Contents/MacOS/PeekKit --quicklook-test /absolute/path/to/folder
```

The latter uses the system Quick Look view; it is a diagnostic, not a substitute for Finder integration testing.

## Local baseline (2026-10-30)

The publication tree was rebuilt locally and its 28 analysis checks and 22 renderer checks rerun successfully. Reports: [analysis](validation/analysis.json), [renderer](validation/renderer.json).

- 28/28 scanner/model checks: recursion, extension aggregation, logical/allocated rankings, genuine sparse allocation, packages, hidden scope, hard links, symlinks/FIFO, real unreadable files/directories, invalid roots, entry/depth/time limits, incremental updates, cancellation, descriptor release, stale generations and model lifetime.
- 22/22 Markdown/preview renderer checks: formatting, original source, encoding, input limits, sanitization, bundled resources and blocked remote images.
- Real Finder interactions: grid/list, size sorting, filtering without changing totals, hidden toggle/re-scan, child navigation, empty-folder layout, footer spacing, image/PDF/text and Markdown Preview/Source.
- Installed Quick Look extension: all 25,000 synthetic files measured, even while browsing showed its independent first-20,000 cap; 4.8 seconds, repeat 4.9 seconds.
- Optimized isolated scanner: 1.857 seconds for the same count; maximum observed main-actor heartbeat delay 13.1 ms. These measurements isolate different scopes and are not general guarantees.

The installed build was locally development-signed. The publication build defaults to ad-hoc signing and must be revalidated for installation on a clean Mac.

## Not yet verified

Real cloud placeholders/provider hydration, actual network or cross-volume mounts, million-entry trees, Intel and other macOS releases. Cloud skip policy has deterministic unit tests only. Stop/close cancellation is exercised by model tests; the UI Stop control was observed, but no timed manual close-cancellation measurement was recorded.

## CI

The workflow builds the application and runs scanner/model tests on a macOS arm64 runner. It does not install the app, test real Finder integration, access cloud files or publish releases. The initial release passed its GitHub Actions build and scanner/model tests on 2026-10-30: [verified run](https://github.com/LujiaChen/PeekKit/actions/runs/41142241480). The workflow does not cover renderer UI or Finder interactions.

Runner reference: [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

## 1.3 final release suites

Run Tests/registration.sh, Tests/run.sh, Tests/archive.sh, Tests/browser.sh, build.sh, Tests/content.sh and Tools/test-renderer.sh from a clean checkout. Final local total: 158 passed, 0 failed. CI runs all six suites and both extension builds. [Final Finder matrix, measurements and limitations](VALIDATION-1.3.md).

## 1.3.1 verification

From a clean checkout run Tests/registration.sh, Tests/run.sh, Tests/archive.sh, Tests/pdf.sh, Tests/browser.sh, build.sh, Tests/content.sh and Tools/test-renderer.sh. PDF fixtures are synthetic; 7z uses Python stdlib plus checked-in official synthetic fixtures with provenance/hashes. No external CLI or Python packages are required. [Results and Finder boundaries](VALIDATION-1.3.1.md).

## 1.3.2 stability checks

Run the same complete source-build suite as 1.3.1. New checks cover CJK table/viewport geometry, light/dark semantic text colors, lazy page menus, cancellation before view creation, 20 repeated representable teardowns and 100 redundant PDF updates preserving view/document identity and zoom. The final suite has 231 checks (PDF 25, Browser 40; all prior checks retained). See [profiling, Finder results and limits](VALIDATION-1.3.2.md).

## Distribution and installation helper

After a build, run `./Tests/distribution.sh .build/PeekKit.app`. The 19 checks use
real macOS codesign/xattr tools on temporary copies only, including paths with
spaces, no-op validation, explicit quarantine consent, recursive scoped removal,
preservation of unrelated xattrs and both entitlements, repeated preparation,
tampering, symlink rejection, mismatched versions, network entitlements, missing
and additional extensions. Tests never register their temporary apps, reset Quick
Look, or change the installed copy. JSON results are written to
`.build/test-results/Distribution-Validation.json`.

Both CI and the release workflow run these tests. The release workflow additionally
creates/validates a DMG and checks archive hashes. Packaging/registration success
is not proof of another Mac's Gatekeeper acceptance or Finder extension activation.
A fresh-machine download/quarantine/enablement test remains necessary; do not label
an ad-hoc artifact notarized. Use `install-app.sh --check-only` for non-mutating
installation diagnostics and `--prepare-only` for isolated preparation tests.
