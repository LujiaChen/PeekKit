# Third-party notices

PeekKit's original source is licensed under the [MIT License](LICENSE). Bundled third-party components retain their own licenses:

| Component | Bundled version | License | Notice |
| --- | --- | --- | --- |
| [Marked](https://github.com/markedjs/marked) | 18.1.2 | MIT | [Full text](Resources/Vendor/marked-LICENSE.txt) |
| [DOMPurify](https://github.com/cure53/DOMPurify) | 3.4.17 | Apache-2.0 OR MPL-2.0 | [Apache license / notices](Resources/Vendor/DOMPurify-LICENSE.txt), [MPL text](Resources/Vendor/DOMPurify-LICENSE-MPL.txt) |
| [PeekX](https://github.com/altic-dev/PeekX) | Functional reference at commit `89147aed103b8f7987cf253e50bf523a8d6048ca` | MIT, Copyright (c) 2025 ALTIC | [Reference acknowledgment and full license](Resources/Vendor/PeekX-Reference-LICENSE.txt) |

The folder analyzer is independently implemented. No PeekX implementation code was copied. Its README and source were reviewed as a functional reference. PeekKit uses its own bounded recursive metadata traversal and existing offline Markdown renderer.

The Apple frameworks and SF Symbols used by the application are supplied by macOS and Apple's SDKs; they are not redistributed as source dependencies. Documentation screenshots show PeekKit running with synthetic sample files.

Version 1.2 adds independently implemented lexical highlighting and heading navigation; no new vendored library is introduced. Existing license texts remain unchanged.

Archive public headers: libarchive v3.7.7, BSD license retained at Vendor/LibArchive/COPYING; provenance in Vendor/LibArchive/PROVENANCE.md. Decoding uses the OS library, not an included third-party executable.

1.3.1 adds public-domain liblzma API headers only, pinned to XZ Utils v5.4.7. Individual notices and upstream COPYING remain in Vendor/Lzma, with exact hashes/source URLs in PROVENANCE.json. No XZ tool/decoder implementation/binary is redistributed; runtime uses macOS public liblzma. PeekKit's bridge and 7z parser are original MIT source. The public 7z specification and libarchive's 7z source were engineering references; no decoder implementation was copied. Synthetic test fixture provenance: Tests/fixtures/README.md. 7-Zip is not bundled.
