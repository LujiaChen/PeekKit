# PeekKit 1.3.0 release candidate validation

Status: **candidate, not yet approved for merge/release**. Builds target Apple Silicon/macOS 14+. Local environment: Apple M5, 10 logical processors, macOS 27.2 (26B123). Other OS versions/Intel are not integration claims.

## Architecture and build

ArchiveReader uses raw fixed-window GZip/BZip2 filtering before bounded TAR preflight; ZIP local/central preflight forbids unapproved codecs and oversized metadata. See [ARCHIVES.md](ARCHIVES.md) for actual budgets and cooperative deadline semantics. A separate XPC helper was considered; it would require additional IPC/signing/lifecycle work and would not automatically impose memory limits. This candidate instead reduces the native parser input surface before use. Public system libarchive and header BSD notices/provenance remain unchanged.

FolderEntry caches lstat allocation/creation/access metadata on the listing worker. FolderOrdering supports these fields plus extension. FolderBrowser persists optional columns with AppStorage and horizontally scrolls wide lists. No metadata reads occur in row rendering. FileInspection reads resident images/PDFs at most 8 MB for dimensions/page count. Archive Markdown at most 128 KB uses the existing escaped/sanitized offline body/native attributed-text path with safe link handling; archive-relative resources are never resolved.

Source build requires Xcode, no paid credentials or package manager:

```sh
./Tests/run.sh
./Tests/archive.sh
./Tests/browser.sh
./build.sh
./Tests/content.sh
./Tools/test-renderer.sh
```

All scripts must pass. CI builds host and both extensions from a clean checkout and executes the same five suites. Default signing is ad-hoc; this is not notarization. Diagnostic snapshot flags render actual app content using synthetic inputs and are not Finder interaction automation.

## Automated results

148 passed / 0 failed: analysis 28, browser/inspector/ordering 35, content/export/security 20, renderer/lifecycle 28, archive 37. Reports: [analysis](validation/1.3/analysis.json), [browser](validation/1.3/browser.json), [content](validation/1.3/content.json), [renderer](validation/1.3/renderer.json), [archive](validation/1.3/archive.json).

Added cases cover mismatched ZIP headers, CRC corruption, TAR checksum/conflict errors, truncated compressed streams, oversized PAX metadata, a compressed header bomb, 5,000-entry TAR, 8 MiB highly compressible ZIP, repeated previews and cancellation of an active scan. Existing sparse/hard-link/cloud-policy/descriptor/lifecycle/Markdown security tests remain. This is deterministic regression testing, not fuzzing or proof of general memory safety.

## Scoped performance observations

The archive runner records its own wall time and getrusage peak RSS, excluding compiler memory. RSS includes all archive tests, including rejecting the 129 MiB header-bomb fixture, and is not per-preview RSS or a hard cap. Warm local single-run measurements; no before/after speedup claim:

```json
{
  "cancellationSeconds": 2.045833389274776e-05,
  "largeTar5000Seconds": 0.023807874997146428,
  "largeZip8MiBSeconds": 0.002582458342658356,
  "os": "Version 27.2 (Build 26B123)",
  "peakRSSBytes": 240730112,
  "processors": 10,
  "twentyZipPreviewsSeconds": 0.001265333325136453
}
```

The browser runner retains its 20,000-entry cached-presentation microbenchmark; it excludes painting and initial worker sort. Full-app sampled RSS, slow/cloud providers and long-duration resource leakage remain unverified.

## Actual screenshots

These are real NSHostingView/app content snapshots from the built standalone reader, using synthetic files. Some view states are selected by diagnostic flags. They are not mockups, screenshots of Finder Space, a keyboard interaction test or a VoiceOver audit.

![Archive tree, dark](images/1.3/archive-tree.png)
![Archive directory, light](images/1.3/archive-directory.png)
![Inspector](images/1.3/inspector.png)
![List columns](images/1.3/columns.png)
![Storage analysis](images/1.3/analysis.png)

## System integration and release gate

The stable /Applications/PeekKit.app 1.2.0 has not been replaced. Temporary QA bundles used separate identifiers and ad-hoc signatures to avoid replacing it. System QLPreviewView requests were made for ZIP/TAR/TGZ/TBZ2. Unified logs prove a QA extension process was launched through XPC; the available view-cache capture cannot reliably capture remote views and did not prove that archive rows were displayed. A direct request with duplicate registered production identifiers fell back to the system ZIP icon. These results are **inconclusive for successful archive integration**, not passing Finder tests.

There is no usable visible Finder/keyboard/VoiceOver automation surface exposed in this session. Finder Space-bar navigation, rapid target switching, close/reopen during decoding, actual inspector sheets inside the extension, preference toggling and full keyboard/focus/tab/VoiceOver interaction remain unverified. Accessibility labels and code paths alone are not proof. Startup light/dark layouts were visually inspected. Stable registration is restored after QA cleanup.

**Do not merge/tag/release until actual archive Quick Look display and interactions are confirmed in a desktop test.** Candidate sources, security hardening, tests, documentation and screenshots are ready for that verification. XZ, 7z, RAR, ZIP64, encryption, split/self-extracting archives, sparse/global TAR extensions and nested archive browsing remain unsupported. Per-entry compressed sizes are unavailable. Native library/OS image/PDF decoders remain trusted native code, not hard RSS/CPU-isolated processes.
