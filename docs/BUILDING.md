# Building PeekKit

## Requirements

- Apple Silicon Mac, macOS 14+
- Xcode with its macOS SDK selected as the active developer directory
- Apple's Swift compiler, `codesign` and `iconutil` (provided by Xcode/macOS)

No Swift packages, JavaScript package installation or network access are needed by the build.

## Build

```sh
./build.sh
```

Default app: `.build/PeekKit.app`. Default compiler/icon intermediates: `.build/intermediates/`. The output app must not already exist; move a previous build aside before building again.

Optional output and signing identity:

```sh
PEEKKIT_SIGN_IDENTITY='Your signing identity' ./build.sh /absolute/path/to/a/new/PeekKit.app
```

Omit the identity for ad-hoc signing. `PEEKKIT_BUILD_DIR` overrides the intermediate directory. The current build targets `arm64-apple-macosx14.0`; Intel/universal binaries are not supplied.

The script builds the host and both extensions, copies local renderer assets/notices, generates the icon, signs inside-out and verifies the resulting bundle. Do not keep multiple registered app copies when testing Finder integration.

## Source map

| Path | Purpose |
| --- | --- |
| `Sources/App.swift` | Host app and diagnostic launch options |
| `Sources/FolderBrowser.swift` | Browser, navigation, thumbnails, image/PDF/text/native Markdown detail |
| `Sources/FolderAnalysis.swift` | Bounded metadata traversal and aggregate snapshots |
| `Sources/FolderAnalysisModel.swift` | Background worker, task generations and cancellation |
| `Sources/FolderAnalysisView.swift` | Summary and expandable analysis UI |
| `Sources/PreviewController.swift` | Folder Quick Look extension and lifecycle |
| `Sources/PreviewProvider.swift` | Direct Markdown Quick Look reply |
| `Sources/MarkdownDocument.swift` | Bounded reading and offline HTML generation |
| `Sources/MarkdownContent.swift`, `Sources/PreviewViewController.swift` | Native/host Markdown presentation |
| `Resources/` | Extension configuration, local renderer, bundled notices |
| `Tests/` | Scanner/model regressions |
| `Tools/MakeIcon.swift` | Procedural application icon |

Finder runs the extensions on demand. No global hotkey listener, login item, daemon or main app background process is installed.

## 1.2 modules and production packaging

FolderEntry and FolderOrdering are immutable metadata/ordering helpers; FolderModel owns listing, tree requests, cached presentation and cancellation generations. LocalFilePolicy is shared by browsing and explicit content previews. PreviewPayload performs bounded text/PDF/image work on a worker. AnalysisExport serializes scope and bounded results without filesystem writes.

For production signing, set PEEKKIT_SIGN_IDENTITY to a Developer ID Application identity. Tools/package.sh /path/to/PeekKit.app /new/output/directory additionally requires PEEKKIT_NOTARY_PROFILE naming an existing notarytool keychain profile. It verifies notarization/stapling/Gatekeeper before producing the notarized ZIP. This credentialed path remains untested locally; no secrets are needed for default builds or CI.

## 1.3 stable source build

The existing build command builds the app and both extensions. ArchiveReader preflights ZIP/TAR metadata and bounded raw GZip/BZip2 output; the existing folder extension additionally registers the concrete TGZ/TBZ2 types. No new service, paid credential or notarized binary is required. See [archive architecture](ARCHIVES.md) and [final validation](VALIDATION-1.3.md).

## 1.3.1 source map

FileBackedPDF pins local PDF descriptors; PDFContent owns the native viewer/navigation. SevenZipReader validates a narrow grammar and uses public system liblzma through Vendor/Lzma/LzmaBridge.h. Only public-domain API headers are bundled; no decoder binary. Existing offline build and ad-hoc signing require no paid credentials. Architecture: [PDF](PDF.md), [archives](ARCHIVES.md).

## 1.3.2 lifecycle and native Markdown

PDFContent preserves its PDFView/document identity across unrelated SwiftUI updates. `show(nil)` also clears a deferred descriptor lease before view loading. Native Markdown uses a viewport-sized NSTextView and normalized AppKit table cells; semantic body colors are restored after HTML import so the hosted view controls light/dark text colors. The offline sanitization, input caps and CSP remain unchanged. See [1.3.2 validation](VALIDATION-1.3.2.md).

## Credential-free release packaging

`Tools/package-adhoc.sh` is separate from the credentialed notarization path above:

```sh
./build.sh
./Tests/distribution.sh .build/PeekKit.app
./Tools/package-adhoc.sh .build/PeekKit.app .build/release
```

Use a clean, committed checkout and a newly built app; the packager refuses dirty
source or an existing output directory. It verifies arm64, matching app/extension
versions, signatures and sandbox entitlements; packages with native ditto/hdiutil;
verifies the DMG; creates a source ZIP from HEAD; and checks SHA-256 digests. ZIP
and DMG include the app, installation helper and verifier, instructions and notices.
The manifest lists all three archives. They are ad-hoc signed, not notarized.

`.github/workflows/release.yml` uses the standard `macos-15` arm64 runner and its
selected Xcode SDK; the deployment target remains macOS 14. It runs the full
regression suite before packaging. Pull requests affecting packaging and manual
workflow runs build/upload test artifacts **without publishing**. Pushing a new
`vMAJOR.MINOR.PATCH` tag whose version matches all three bundle plists builds and
publishes assets using GitHub's token, without Apple credentials. Update version
and build numbers and validate Finder behavior before tagging. CI does not prove
Finder integration. SHA-pinned actions and read-only checkout credentials are used;
only the separate publication job has contents-write permission.

An existing Release retains its notes/draft/prerelease status; assets are uploaded
without clobbering. For a new tag, a stable Release is created with generated notes
and an explicit ad-hoc/notarization notice. Re-running against an already uploaded
asset fails rather than overwriting it. Existing tags/releases are not modified by
merging the workflow. GitHub repository Actions/write-token policy can prevent
publication; the packaging job's downloadable artifacts remain available.
