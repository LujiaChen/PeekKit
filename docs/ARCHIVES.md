# Archive support and safety — 1.3.1

Stable source release. Finder registration has been added to the existing folder extension for ZIP, TAR, gzip and bzip2 content types. ArchiveBrowser is shared with standalone and folder file-detail paths. Standalone rendering is verified; system-host and Finder verification scope is recorded in VALIDATION-1.3.md.

Backend: public libarchive C API linked to the macOS SDK libarchive stub/system library. No private Apple API, subprocess or network is used by the application. Public headers are from upstream v3.7.7; this does not pin or bundle the system decoder version. Updating macOS supplies system-library fixes. Header license is retained in Vendor/LibArchive/COPYING. Header hashes/source URLs are in PROVENANCE.md.

| Format | Development state |
| --- | --- |
| ZIP | Store/deflate only; central directory preflight; ZIP64, multi-volume, encrypted and wrapped/SFX ZIP rejected |
| TAR, TAR.GZ/TGZ, TAR.BZ2/TBZ2 | Raw filter stream expanded under a 128 MiB budget, fixed TAR headers preflighted, whole archive validated before listing |
| TAR.XZ/TXZ | Disabled: upstream XZ decoder uses an effectively unlimited LZMA memory limit; output-byte limits alone do not bound dictionary allocations |
| 7z | Copy/LZMA1/LZMA2; bounded solid/compressed headers; see 1.3.1 section below |
| RAR | Disabled |

Engineering choice: harden the current decoder (Option B). A helper/XPC service would add a second IPC/lifecycle/signing surface and does not itself impose an RSS ceiling. For enabled formats, parser inputs can instead be bounded before native metadata parsing. No private API or process-wide resource limit is used.

Compressed inputs are at most 64 MiB. GZip/BZip2 are first read as **raw streams**, with only fixed-window filters enabled, in 64 KiB blocks, into at most 128 MiB. Nested filters are rejected. The resulting TAR is then parsed without compression filters. Preflight checks every 512-byte header/checksum/payload boundary and requires two zero terminator blocks. Special/link/global/sparse entries are rejected before native header parsing. Local PAX/GNU long-name metadata is at most 32 KiB/header and 2 MiB total; PAX keys are strictly allowlisted and declared record lengths checked; size/link/sparse overrides are rejected.

ZIP preflight checks complete central directory bounds, local/central method/name/flag consistency, nonoverlapping payloads, known sizes/CRC when not using descriptors, store/deflate only, no ZIP64 extras, 1 KiB extras and 4 KiB names, 8 MiB central name/extra metadata. This prevents a local header from selecting a decoder that was not approved by central-directory checks.

Common limits: individual decoded file 32 MiB; aggregate decoded file bytes 128 MiB; 20,000 entries/hierarchy nodes; 64 path components; 4096 bytes/path; 4 MiB explicit path metadata. Oversized/invalid inputs fail closed. A 10-second deadline and Task cancellation are checked between native calls and during Swift header preflight. These are **cooperative**, not a hard wall-clock, CPU or RSS guarantee. No library is claimed free of implementation vulnerabilities; OS updates supply system decoder fixes. The enabled fixed-window codecs and bounded plain metadata remove the prior unbounded dictionary/header expansion path; stress measurements are finite evidence, not proof of universal memory safety.

Every file is streamed through a 64 KiB buffer for integrity and decoded-byte accounting. Only a selected file is retained for preview. No archive paths are used as filesystem destinations, no temporary extraction occurs, and no entry is launched. Absolute/traversal/backslash/colon/control-character paths, duplicate/conflicting paths, symbolic links, hard links and special entries fail the entire request. There is no partial listing presented as complete.

Views: expandable tree or current-directory list, path search, parent/root navigation, keyboard focus/Return and available metadata. Tree order is hierarchical path order; field sorting applies to directory lists. Per-entry compressed sizes are unavailable and are not fabricated. Text is bounded to 128 KB; Markdown at most 128 KB uses the shared escaped-HTML native renderer with a source toggle and no archive-relative resources; images/PDFs decode from in-memory bytes. Image/PDF decoding runs on a worker and inherits OS decoder risks; it is not a hard RSS-isolated process. Nested archives are not recursively opened.

Inspector: dimensions and PDF page count are read lazily for locally resident files at most 8 MB; unavailable/oversized/cloud metadata remains omitted. Type is inferred from extension. Folder options persist Type, logical Size, Allocated, Created, Modified, Accessed and Extension columns; Name remains visible. Columns use cached worker metadata and horizontal scrolling.

Tests/archive.sh synthesizes ZIP/TAR/GZip/BZip2 fixtures, Unicode paths, empty ZIP, malformed/truncated/encrypted inputs, links/special entries, traversal, duplicate paths, excessive depth/entries/input/decompressed size and cancellation. It also checks that XZ is rejected. Actual standalone screenshots, test metrics and remaining integration/accessibility limits are recorded in VALIDATION-1.3.md. XZ/RAR remain disabled.

## 7z — 1.3.1 support and architecture

Supported: **Copy, LZMA1 and LZMA2**, including bounded solid blocks and one compressed-header layer. RAR/XZ, encryption, external metadata, anti-files, multi-volume/wrapped archives, multiple-coder/filter chains (including BCJ/Delta/PPMd) and recursive nested-archive browsing remain unsupported. Existing ZIP/TAR protections are unchanged.

SevenZipReader independently implements a restricted grammar from the [public specification](https://github.com/ip7z/7zip/blob/main/DOC/7zFormat.txt). The general libarchive 7z parser is not enabled. Its [upstream implementation](https://github.com/libarchive/libarchive/blob/v3.7.7/libarchive/archive_read_support_format_7zip.c) can process compressed metadata before callers see entries, so a post-entry output limit alone is insufficient. A helper was considered; isolation alone would not create an RSS limit. This design validates headers in Swift before invoking one narrow raw system-liblzma coder.

Signature/start/next-header CRCs and integer/range bounds are checked. Plain and decoded headers are ≤1 MiB; one simple input/output coder per folder. Dictionary properties are checked before initialization: LZMA1 ≤8 MiB with lc+lp≤4; LZMA2 property≤22. The C bridge also rejects raw-decoder memory estimates above 16 MiB, including dictionary/probability tables. This estimate is not total process RSS. Known-size LZMA1EXT handles ordinary no-end-marker and end-marked streams where provided by the OS; unavailable codec capabilities fail safely.

Compressed input ≤64 MiB; decoded solid blocks combined ≤128 MiB; individual files ≤32 MiB; ≤20,000 files/streams/hierarchy nodes; existing 4096-byte/64-component path limits. Solid block output is bounded and split by validated substream sizes. Packed, folder and file CRCs are verified when present, with exact input/output consumption. Invalid UTF-16 names, duplicate/conflicting paths, symlink/special/reparse attributes and unknown file properties fail closed. Paths never become extraction destinations.

No 7-Zip executable or decoder binary is shipped. Only public-domain API headers from XZ Utils 5.4.7 are vendored, with hashes/provenance in Vendor/Lzma/PROVENANCE.json; runtime uses the public macOS liblzma. OS updates supply decoder fixes. Native decoding runs on a worker; cancellation and the 10-second deadline are checked between calls and throughout metadata processing. A raw decode cannot be forcibly interrupted. These are cooperative limits, not hard CPU/RSS ceilings or proof against native-code vulnerabilities. No new service or network permission.

Ordinary resident PDFs use the separate [file-backed reader](PDF.md); archived PDFs remain limited to 32 MiB in memory. Current synthetic fixtures, actual Finder evidence and limitations: [1.3.1 validation](VALIDATION-1.3.1.md).
