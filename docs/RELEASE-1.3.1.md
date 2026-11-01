PeekKit **1.3.1 (build 7)** is a stable source release for Apple Silicon/macOS 14+.

### Large PDFs
- File-backed native PDFKit viewer replaces the 50 MB whole-Data preview gate.
- Continuous scrolling, zoom, Previous/Next, page number + Go, page count and Fit.
- No-follow descriptor pinning, local/cloud residency checks, asynchronous opening and explicit invalid/locked/unreadable errors. Archive PDFs keep the bounded in-memory path.
- The private 86 MB/712-page PDF was verified locally in actual Finder folder browsing; no textbook content is included.

### Safe 7z subset
- Copy, LZMA1 and LZMA2, including bounded solid streams and compressed headers; integrated tree/list/search/navigation and text/image/PDF/Markdown previews.
- Independent restricted header parser, 8 MiB dictionary cap, 16 MiB raw-decoder memory-estimate budget, 1 MiB header budget; existing 64 MiB input, 32 MiB file, 128 MiB decoded-total and 20,000-entry limits.
- Encryption, filter chains/other codecs, unsafe paths/links, invalid metadata/checksums and resource-limit violations fail closed. No disk extraction or execution.

### Verification and limits
218 checks passed from a clean clone, with host and both extensions built/signature-verified. Real Finder tests and genuine synthetic screenshots: [validation](https://github.com/LujiaChen/PeekKit/blob/v1.3.1/docs/VALIDATION-1.3.1.md).

ZIP Store/Deflate, TAR, TGZ/TAR.GZ and TBZ2/TAR.BZ2 remain supported. XZ, RAR, ZIP64, encrypted archives and recursive nested browsing remain unsupported. Native calls and the 10-second deadline are cooperative; codec-memory estimates are not process RSS ceilings. PDFKit image/page caches can use substantial RAM. Some keys are reserved by Finder; use PDF Go/visible controls. Complete VoiceOver, real cloud providers, other Macs/OS versions and prolonged stress are not claimed verified.

### Build/install
```sh
git clone --branch v1.3.1 https://github.com/LujiaChen/PeekKit.git
cd PeekKit
./build.sh
```
Move `.build/PeekKit.app` to Applications, open it once, enable PeekKit Folder and PeekKit Markdown in Quick Look settings, and keep one registered installed copy. Preserve a temporary old copy until verified. [Installation](https://github.com/LujiaChen/PeekKit/blob/v1.3.1/docs/INSTALL.md), [PDF architecture](https://github.com/LujiaChen/PeekKit/blob/v1.3.1/docs/PDF.md), [archive limits](https://github.com/LujiaChen/PeekKit/blob/v1.3.1/docs/ARCHIVES.md).

Attached source ZIP and SHA-256 manifest identify the tagged tree. No notarized binary is distributed; local builds are ad-hoc signed and require no paid Apple account or security bypass. Public-domain liblzma API headers are bundled with notices/provenance; runtime uses the OS library, with no 7-Zip CLI dependency.
