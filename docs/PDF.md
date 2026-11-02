# File-backed PDF preview — 1.3.2

## Root cause and fix

1.3.0 required PDF size <50,000,000 bytes and read the entire PDF into Data before PDFDocument(data:). Larger files returned unsupported and displayed a generic icon. This was reproduced in Finder's folder browser with an 86,264,556-byte resident PDF.

FileBackedPDF now opens a resident regular file with O_NOFOLLOW, O_NONBLOCK and O_CLOEXEC, verifies fstat/dataless flags, then calls PDFDocument(url:) on /dev/fd/<descriptor>. The session and active viewer retain the descriptor, pinning the opened inode against later pathname/symlink replacement. Errors, cancellation and teardown close it. Existing LocalFilePolicy and Quick Look security scope remain in force; cloud-only files are rejected without requesting downloads.

Opening and page-count metadata run on a worker. PDFView draws visible pages from a file-backed document; PeekKit does not create a whole-file Data buffer or rasterize the entire document. PDFKit may cache data and remains a native-code trust boundary, without hard CPU/RSS guarantees. A native open cannot be forcibly interrupted; cancellation rejects stale results and releases the descriptor after that call returns.

PDFViewerController provides continuous vertical scroll, Previous/Next, a lazy native page-selection menu, page count, zoom in/out and Fit. Page numbers are clamped; unrelated SwiftUI updates preserve scroll/zoom; document changes and teardown clear the old document/lease. The menu avoids text-field keyboard interception by Finder. Cancellation before view loading clears both the deferred document and descriptor lease.

Invalid, locked, missing, unreadable and nonresident PDFs show explicit errors. Unlock protected PDFs in a dedicated app. Inspector content metadata remains limited to resident files ≤8 MB; a large PDF can render even if its inspector page count is omitted. Archive PDFs retain the separate ≤32 MiB PDFDocument(data:) path, with no extraction or archive-relative resource access.

## Validation

Tests/pdf.sh creates a valid 87 MB sparse incremental PDF with 40 pages; checks navigation/clamping, zoom, switching, teardown, error recovery, symlinks, cancellation and descriptor cleanup. Sparse data proves removal of the old size gate, not complex-image performance. The private 86 MB/712-page textbook was tested locally in Finder; no textbook content or screenshots are committed. See [current validation and profiling](VALIDATION-1.3.2.md). Real cloud providers, complete VoiceOver operation, other OS versions and prolonged stress remain unverified. No network entitlement or security bypass was added.

## Resource behavior

A system Time Profiler recording of the real Finder process observed JPEG2000 decoding and PDFKit's visible-page-triggered text recognition. Three finite open/navigate/zoom/scroll/leave cycles recovered to roughly 52–55 MB physical footprint, with near-zero idle CPU; closing Quick Look reached 50 MB. These observations did not establish a large PDF leak or reproduce the reported 5.39 GB event. Native caches and decoding still have no hard CPU/RSS ceiling. Allocations attachment failed in this environment; VM summaries, Time Profiler and content-free leaks scans were used instead. A stable 384-byte CFData leak report was not attributed to app code. No private APIs or forced cache eviction are used.
