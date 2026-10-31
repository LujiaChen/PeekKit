# Archive support and safety — 1.3.0

Stable source release. Finder registration has been added to the existing folder extension for ZIP, TAR, gzip and bzip2 content types. ArchiveBrowser is shared with standalone and folder file-detail paths. Standalone rendering is verified; system-host and Finder verification scope is recorded in VALIDATION-1.3.md.

Backend: public libarchive C API linked to the macOS SDK libarchive stub/system library. No private Apple API, subprocess or network is used by the application. Public headers are from upstream v3.7.7; this does not pin or bundle the system decoder version. Updating macOS supplies system-library fixes. Header license is retained in Vendor/LibArchive/COPYING. Header hashes/source URLs are in PROVENANCE.md.

| Format | Development state |
| --- | --- |
| ZIP | Store/deflate only; central directory preflight; ZIP64, multi-volume, encrypted and wrapped/SFX ZIP rejected |
| TAR, TAR.GZ/TGZ, TAR.BZ2/TBZ2 | Raw filter stream expanded under a 128 MiB budget, fixed TAR headers preflighted, whole archive validated before listing |
| TAR.XZ/TXZ | Disabled: upstream XZ decoder uses an effectively unlimited LZMA memory limit; output-byte limits alone do not bound dictionary allocations |
| 7z, RAR | Not enabled or advertised; backend memory budgets and malicious-format fixtures are not validated |

Engineering choice: harden the current decoder (Option B). A helper/XPC service would add a second IPC/lifecycle/signing surface and does not itself impose an RSS ceiling. For enabled formats, parser inputs can instead be bounded before native metadata parsing. No private API or process-wide resource limit is used.

Compressed inputs are at most 64 MiB. GZip/BZip2 are first read as **raw streams**, with only fixed-window filters enabled, in 64 KiB blocks, into at most 128 MiB. Nested filters are rejected. The resulting TAR is then parsed without compression filters. Preflight checks every 512-byte header/checksum/payload boundary and requires two zero terminator blocks. Special/link/global/sparse entries are rejected before native header parsing. Local PAX/GNU long-name metadata is at most 32 KiB/header and 2 MiB total; PAX keys are strictly allowlisted and declared record lengths checked; size/link/sparse overrides are rejected.

ZIP preflight checks complete central directory bounds, local/central method/name/flag consistency, nonoverlapping payloads, known sizes/CRC when not using descriptors, store/deflate only, no ZIP64 extras, 1 KiB extras and 4 KiB names, 8 MiB central name/extra metadata. This prevents a local header from selecting a decoder that was not approved by central-directory checks.

Common limits: individual decoded file 32 MiB; aggregate decoded file bytes 128 MiB; 20,000 entries/hierarchy nodes; 64 path components; 4096 bytes/path; 4 MiB explicit path metadata. Oversized/invalid inputs fail closed. A 10-second deadline and Task cancellation are checked between native calls and during Swift header preflight. These are **cooperative**, not a hard wall-clock, CPU or RSS guarantee. No library is claimed free of implementation vulnerabilities; OS updates supply system decoder fixes. The enabled fixed-window codecs and bounded plain metadata remove the prior unbounded dictionary/header expansion path; stress measurements are finite evidence, not proof of universal memory safety.

Every file is streamed through a 64 KiB buffer for integrity and decoded-byte accounting. Only a selected file is retained for preview. No archive paths are used as filesystem destinations, no temporary extraction occurs, and no entry is launched. Absolute/traversal/backslash/colon/control-character paths, duplicate/conflicting paths, symbolic links, hard links and special entries fail the entire request. There is no partial listing presented as complete.

Views: expandable tree or current-directory list, path search, parent/root navigation, keyboard focus/Return and available metadata. Tree order is hierarchical path order; field sorting applies to directory lists. Per-entry compressed sizes are unavailable and are not fabricated. Text is bounded to 128 KB; Markdown at most 128 KB uses the shared escaped-HTML native renderer with a source toggle and no archive-relative resources; images/PDFs decode from in-memory bytes. Image/PDF decoding runs on a worker and inherits OS decoder risks; it is not a hard RSS-isolated process. Nested archives are not recursively opened.

Inspector: dimensions and PDF page count are read lazily for locally resident files at most 8 MB; unavailable/oversized/cloud metadata remains omitted. Type is inferred from extension. Folder options persist Type, logical Size, Allocated, Created, Modified, Accessed and Extension columns; Name remains visible. Columns use cached worker metadata and horizontal scrolling.

Tests/archive.sh synthesizes ZIP/TAR/GZip/BZip2 fixtures, Unicode paths, empty ZIP, malformed/truncated/encrypted inputs, links/special entries, traversal, duplicate paths, excessive depth/entries/input/decompressed size and cancellation. It also checks that XZ is rejected. Actual standalone screenshots, test metrics and remaining integration/accessibility limits are recorded in VALIDATION-1.3.md. XZ/7z/RAR remain disabled.
