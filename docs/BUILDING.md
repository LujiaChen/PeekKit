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
