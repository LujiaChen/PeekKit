# 1.3.2 candidate validation — not release-ready

Recorded locally on 2026-11-02. Version markers are 1.3.2/build 8; no v1.3.2 release has been published by this work.

## Verified fixes

- PK-003: the native folder Markdown path created a zero-sized NSTextView whose document frame did not track its viewport. Text remained in the accessibility tree but was visually clipped. MarkdownScrollView now sizes its text container and document frame from the viewport and measured layout. Native table paragraphs/cells are normalized; HTML row groups are flattened before AppKit import so headers/body share a table. Fixed equal-width columns provide predictable wrapping, with horizontal scrolling for wide tables.
- Actual Finder folder preview of the original local CJK document showed restored headings/body, six continuous table rows, complete dates and readable wrapped cells. Preview/Source switching worked. Light appearance verified; dark appearance and complete VoiceOver operation remain unverified. No private document or screenshot is included here.
- PK-002: Finder intercepted keyboard input rather than delivering digits to the PDF text field. A native lazy page-selection menu replaces the unusable field/Go control. At most 101 items are built at a menu level; submenu delegates stay alive and item identities remain stable across repeated accessibility queries. Real Finder navigation to page 100 and Previous/Next through page 105 succeeded. This does not claim text-entry support.

## Retained implementation verification

All existing tests remain. The retained candidate passed 225 checks: Registration 11, Analysis 28, Archive 79, PDF 21, Browser 38, Content 20, Renderer 28. The additional checks cover CJK table content, viewport layout, continuous native table borders, menu choices, menu navigation, lazy bounds and accessibility-query stability.

The main application and both Quick Look extensions built and passed strict deep ad-hoc signature verification. Local registration inspection found one Folder and one Markdown extension under /Applications/PeekKit.app, both 1.3.2/build 8. This installed application is a temporary QA candidate, not a released-source build. The original 1.3.1 installation remains backed up locally. CI and clean-checkout release verification are not complete.

## PK-001 remains a release blocker

The original 86,264,556-byte, 712-page local PDF renders. Sampled image resources on tested pages include images around 2900 × 3800 pixels; compressed file size is not decoded image size. This observation does not by itself prove the cause of all memory growth or a leak.

One real Finder continuous-layout run (pages 100–105, zoom and scroll) reached sampled RSS 1,212,976 KiB and ps CPU 237.1%. A single-page-layout experiment reached RSS 1,098,816 KiB and CPU 209.7%, ending near 740,592 KiB/0% CPU. A separate fresh-rendering-session experiment reached RSS 801,520 KiB and CPU 333.9%, ending near 367,264 KiB/0% CPU. Workload timing differs; these are diagnostic observations, not a controlled speedup claim. The reported 5.39 GB usage has not been reproduced. RSS is not Activity Monitor memory footprint, and ps CPU is a sampled utilization estimate.

Experimental per-page document/view lifetime changes did not pass the new old-rendering-document release assertion. They were excluded from the retained candidate; their source/patch and failed diagnostics remain locally outside the repository. The retained candidate preserves the existing continuous file-backed PDF path and does not claim PK-001 fixed. There is no hard PDFKit memory/CPU limit.

Measurements were finite with a diagnostic stop threshold of 1.5 GiB RSS for the extension. This threshold belongs to the external sampler, not the app. Prolonged repeated-session recovery, equivalent before/after profiling, final dark-mode checks and full Finder regression coverage are still required before stable publication. No PDF size cap was raised or added; ZIP/TAR/7z limits and Markdown security policies are unchanged.
