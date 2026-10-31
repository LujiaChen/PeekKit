# Changelog

## 1.3.0 — Archive Browsing & File Inspector

- Fix concrete TGZ/TBZ2 Quick Look type registration; final Finder checks cover supported archives and filename aliases.

- Add an asynchronous metadata-only file information panel for existing file previews.
- Archive tree/directory browsing, search, sorting and bounded in-memory previews for ZIP/TAR/GZip/BZip2 TAR. Unsafe entries fail closed.
- Persisted Type/Modified/Size list-column toggles; bounded local image/PDF inspector metadata.
- Bounded raw filter expansion, fixed-header TAR preflight and ZIP local/central consistency checks; malicious metadata and compressed-header bomb regressions.
- Native safe Markdown previews for selected entries; cancellation controls and expanded cached list columns.
- Authentic standalone snapshots and scoped memory/timing measurements; Finder/VoiceOver limits disclosed.

## 1.2.0 — browsing, analysis and offline rendering

- Lazy, bounded tree view; typed list column, type sorting, contextual open/reveal/copy actions and keyboard navigation.
- Cached visible rows computed on a worker; searching does not restart filesystem scans.
- Recursive top folders alongside top files; overlapping totals and incomplete folders labeled; JSON/CSV clipboard summaries include scope and omissions.
- Shared escaped-HTML Markdown body, bounded lexical highlighting and HTML table of contents, with source-view keyboard support.
- Local residency checks shared by browser and previews; background PDF/image/text/Markdown work and generation-aware WebKit completions.
- Fixed stale thumbnail keys, UTF-8 truncation boundaries, cancellation-triggered error loads and synchronous preview I/O, exported per-file counts and folder-ranking empty-state labels.
- Browser, export, security and arithmetic regressions; CI builds both extensions and runs all test suites.
- Optional Developer ID/hardened-runtime signing and guarded notarization packaging. Default development builds remain unnotarized.

## 1.1.0 — initial public preview

- Recursive logical/allocated size analysis with incremental progress, Stop and Rescan.
- Extension distribution with counts/capacity and top-20 files under either size metric.
- Explicit scope, permission failures, cloud omissions and bounded partial results.
- Existing folder browsing and offline Markdown preview retained.
- Scanner/model regression tests and source-build documentation included.

Earlier local versions combined folder and Markdown previews and fixed empty-folder sizing and footer spacing. This is the first release prepared for public review; cross-machine installation remains unverified.
