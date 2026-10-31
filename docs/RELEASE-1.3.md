PeekKit 1.3.0 (build 6) is an official stable **source release** for Apple Silicon and macOS 14+. No notarized application binary is attached; default local builds are ad-hoc signed and require no paid Apple account.

### Archive browsing
- ZIP Store/Deflate, TAR, TAR.GZ/TGZ and TAR.BZ2/TBZ2.
- Tree/directory browsing, path search, sorting, parent/root navigation and bounded in-memory text, image, PDF and Markdown previews.
- Concrete TGZ/TBZ2 Quick Look type registration fixes the system-icon fallback found by independent Finder QA.
- ZIP local/central checks, bounded raw filter expansion and TAR metadata preflight reject unsafe paths/links, malformed metadata, encryption, unsupported codecs and over-budget inputs. No disk extraction or entry execution.

### File inspector and lists
- Logical/allocated size, readable extension-derived type/UTType, dates, permissions, link status, full path, resident image dimensions and PDF page counts.
- Persisted optional list columns with cached metadata: Type, Size, Allocated, Created, Modified, Accessed and Extension. Name remains visible.
- Existing folder Grid/List/Tree, storage analysis/exports and offline Markdown remain available.

### Verified scope
158 checks passed locally from a clean clone: 28 analysis, 35 browser/inspector/ordering, 20 content/export/security, 28 renderer/lifecycle, 37 archive and 10 registration checks. Main app and both extensions built and passed strict signature verification.

The corrected build was temporarily installed at the production path and exercised with Finder Space for stored/deflated ZIP, TAR, TGZ, TBZ2, both double-suffix aliases, folders and Markdown. Archive navigation, filter/size sort, image/PDF/Markdown details, information sheets, persisted columns, empty/error recovery, larger archive/reopen, and light/dark appearance were checked. Genuine Finder and standalone screenshots and exact test boundaries are in the [validation report](https://github.com/LujiaChen/PeekKit/blob/v1.3.0/docs/VALIDATION-1.3.md).

### Installation
```sh
git clone --branch v1.3.0 https://github.com/LujiaChen/PeekKit.git
cd PeekKit
./build.sh
```
Preserve an older app before replacement. Move `.build/PeekKit.app` to Applications, open it once and enable PeekKit Folder and PeekKit Markdown in Quick Look settings. Keep only one registered installed copy. [Installation/troubleshooting](https://github.com/LujiaChen/PeekKit/blob/v1.3.0/docs/INSTALL.md).

### Limits
Input 64 MiB; decoded entry 32 MiB; decoded aggregate/raw TAR 128 MiB; 20,000 entries/nodes; 64 path components; further explicit metadata bounds. The 10-second limit is cooperative between native calls, not a hard CPU/RSS guarantee. OS archive/image/PDF decoder vulnerabilities remain a native-code trust boundary; keep macOS updated.

XZ, 7z, RAR, ZIP64, encrypted/split/self-extracting archives, unsupported TAR extensions and recursive nested-archive browsing are not supported. Per-entry compressed sizes are unavailable. Archived formatted Markdown is capped at 128 KB. Finder may reserve arrow/Return keys instead of delivering them to the preview; use visible controls in that host. A complete keyboard-only/VoiceOver audit, real cloud-provider integration, other macOS versions and clean-machine installation are not claimed. Immediate close/reopen was checked, while mid-decoder cancellation is proven by harness tests rather than by a timed Finder observation.

The stable source designation does not imply Apple notarization or universal compatibility. Attached source ZIP and SHA-256 manifest identify the exact tagged tree.
