# PeekKit 1.1.0 — initial public preview

Browse folders, analyze their contents, and read Markdown from Finder Quick Look.

## Included

- Folder grid/list, child navigation, sorting, filtering and hidden-file toggle.
- Recursive logical/allocated totals, extension distribution and largest-file lists.
- Background progress, cancellation and explicit partial-result/omission reporting.
- Image, PDF, text and offline Markdown previews.
- Full source, English/Chinese documentation, real screenshots and regression tests.

## Requirements and installation

Apple Silicon, macOS 14+, and Xcode for building. Follow [the build guide](BUILDING.md) and [installation guide](INSTALL.md). No Developer ID–signed/notarized binary is included in this source preview. Cross-machine installation remains unverified.

## Validation and limits

28 analysis/model and 22 renderer checks passed locally. Finder browsing/preview interactions were exercised. Cloud policy is unit-tested; real cloud placeholders and network/cross-volume mounts have not been integration-tested. CI will run after publication and is not yet marked passed.

Scans are bounded to 1,000,000 entries, 128 levels and 60 seconds, with partial results retained. On disk is allocated file blocks, not exclusive or reclaimable APFS space. See the analysis and testing guides for scope.

MIT for original source; third-party notices are retained. PeekX was a functional reference, with the analyzer independently implemented.
