# Archive development status

Not a v1.3 release. Finder registration has been added to the existing folder extension for ZIP, TAR, gzip and bzip2 content types. ArchiveBrowser is shared with standalone and folder file-detail paths. Actual extension selection/loading is not yet verified.

Backend: public libarchive C API linked to the macOS SDK libarchive stub/system library. No private Apple API, subprocess or network is used by the application. Public headers are from upstream v3.7.7; this does not pin or bundle the system decoder version. Updating macOS supplies system-library fixes. Header license is retained in Vendor/LibArchive/COPYING. Header hashes/source URLs are in PROVENANCE.md.

| Format | Development state |
| --- | --- |
| ZIP | Store/deflate only; central directory preflight; ZIP64, multi-volume, encrypted and wrapped/SFX ZIP rejected |
| TAR, TAR.GZ/TGZ, TAR.BZ2/TBZ2 | Streaming libarchive reader; whole archive validated before listing |
| TAR.XZ/TXZ | Disabled: upstream XZ decoder uses an effectively unlimited LZMA memory limit; output-byte limits alone do not bound dictionary allocations |
| 7z, RAR | Not enabled or advertised; backend memory budgets and malicious-format fixtures are not validated |

Bounds: input 64 MiB; individual decoded file 32 MiB; aggregate decoded data 128 MiB; 20,000 entries and hierarchy nodes; 64 path components; 4096 path bytes. A cooperative 10-second deadline and Task cancellation are checked between decoder calls. Native calls cannot be forcibly interrupted, and these checks do not establish a hard CPU/RSS ceiling. Internal decoder allocations/header expansion require further adversarial profiling before release.

Every file is streamed through a 64 KiB buffer for integrity and decoded-byte accounting. Only a selected file is retained for preview. No archive paths are used as filesystem destinations, no temporary extraction occurs, and no entry is launched. Absolute/traversal/backslash/colon/control-character paths, duplicate/conflicting paths, symbolic links, hard links and special entries fail the entire request. There is no partial listing presented as complete.

Views: expandable tree or current-directory list, path search, parent/root navigation, keyboard focus/Return and available metadata. Tree order is hierarchical path order; field sorting applies to directory lists. Per-entry compressed sizes are unavailable and are not fabricated. Text/Markdown currently show UTF-8 source bounded to 128 KB; images/PDFs decode from in-memory bytes. Image/PDF decoding runs on a worker but still needs adversarial profiling before release. Nested archives are not recursively opened.

Inspector: dimensions and PDF page count are read lazily for locally resident files at most 8 MB; unavailable/oversized/cloud metadata remains omitted. Type is inferred from extension. Folder list columns Type, Modified and Size can be toggled from Folder options, persisted by AppStorage; additional date/allocation columns are not implemented.

Tests/archive.sh synthesizes ZIP/TAR/GZip/BZip2 fixtures, Unicode paths, empty ZIP, malformed/truncated/encrypted inputs, links/special entries, traversal, duplicate paths, excessive depth/entries/input/decompressed size and cancellation. It also checks that XZ is rejected. Integration screenshots, actual Finder interaction, VoiceOver, RSS, hard deadlines, archive rapid-switch tests and real cloud providers remain unverified. Do not merge/tag v1.3 until these remaining security and integration gaps are resolved.
