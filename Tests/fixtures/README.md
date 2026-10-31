# Synthetic 7z fixtures

Created with official 7-Zip 26.05 macOS CLI (https://github.com/ip7z/7zip/releases/tag/26.05), downloaded through https://www.7-zip.org/download.html. The CLI is not bundled or required at build/runtime/CI. All content is author-created PeekKit demo text, images and PDF; MIT like PeekKit. No private documents.

Commands: from synthetic sample folder, `7zz a -t7z -m0=lzma2 -md=8m Demo.7z .` (also `-m0=lzma -md=4m`, `-m0=copy`). Encrypted fixture uses `-pfixture-password -mhe=on`. High dictionary fixture uses a 20 MiB string of zeros and `-m0=lzma2 -md=16m` (small files cause 7-Zip to reduce the effective dictionary, so they cannot test this).

Tests/make-sevenzip.py independently synthesizes structural adversarial fixtures using Python stdlib raw LZMA and the public 7z specification: https://github.com/ip7z/7zip/blob/main/DOC/7zFormat.txt. Tests exercise plain and encoded headers, solid streams, checksums and Unicode names.
