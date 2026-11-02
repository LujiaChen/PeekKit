# 1.3.2 stability validation (build 8)

Recorded on 2026-11-02, Apple M5 MacBook Air, 16 GiB RAM, macOS 27.2 (26B123), Xcode/Instruments 27.0. Other OS/hardware combinations are not inferred from this local result.

## PK-001: findings and release decision

The original resident 86,264,556-byte, 712-page image-heavy PDF was tested through **Finder → School folder → Space → PeekKit → PDF**. Three sessions in the same extension process used the same actions: open, select page 100, Next five times, Zoom In twice, Scroll Down four times, Fit, idle, Back to folder; finally close Quick Look. Accessibility inspection and profiler overhead are present, and per-action timing varies. No source document was modified or included in the repository.

| Cycle | Sampled peak RSS (KiB) | Sampled peak ps CPU | Physical footprint after Back, as reported by vmmap |
| --- | ---: | ---: | ---: |
| 1 | 1,199,536 | 241.1% | 52.1M |
| 2 | 1,200,128 | 240.6% | 53.7M |
| 3 | 1,302,176 | 214.5% | 54.6M |

The cumulative physical-footprint peak was reported as 1.5G; after closing Quick Look it was 50.0M, with sampled CPU 0%. CPU time stopped materially increasing when idle (approximately 0.2 seconds added between the third session and the end of the roughly five-minute capture). RSS, physical footprint and Activity Monitor memory are different measures. These observations do not reproduce the reported 5.39 GB incident and do not prove a global RAM bound.

A successful 25-second **system Time Profiler** recording contained 18,637 target-process samples. Inclusive stacks contained TextRecognition in 10,592 samples and libJP2 in 4,189 (overlapping categories). A representative stack ran from `PDFView visiblePagesChanged:` through PDFKit's page analyzer into Vision document recognition. JPEG2000 synthesis and image/color processing were also hot. These are profiler observations of OS internals, not private APIs called by PeekKit. No redundant document/view recreation loop was found; regression tests additionally preserve identity/zoom across 100 repeated updates.

Allocations attachment to the Finder extension failed. A separate Allocations/Leaks launch of the synthetic native test host also failed to acquire its task port. Neither failed recording is counted as successful allocation/leak instrumentation. Equivalent VM summaries, Time Profiler and content-free `/usr/bin/leaks` scans were used. After cycles 1 and 3, leaks reported the **same two CFData blocks / 384 bytes**; no allocation-stack attribution is available. We do not claim zero leaks, nor that these bytes explain the reported gigabytes.

The evidence supports transient native image decoding/recognition/caching, with substantial recovery at the preview boundary. It does **not** establish a reproducible unbounded leak, persistent excessive idle CPU, or crash in this finite workload. Release is acceptable with that limitation disclosed. There is no hard PDFKit CPU/RSS guarantee, no arbitrary PDF file-size cap, and no claimed rendering speedup. The earlier per-page eviction/recreation experiments were rejected and are absent from the release.

One concrete application lifecycle defect was independently reproduced: `show(nil)` before native view loading cleared the deferred document but retained its descriptor lease. The fix also updates that lease. Its new regression failed before the fix and passed afterward; it is **not claimed to explain or fix the 5.39 GB observation**. Loaded PDF rendering remains unchanged, so no before/after performance optimization claim is made. [Sanitized measurement summary](validation/1.3.2-performance.json).

## PK-002 and PK-003

- Finder intercepted number keys instead of delivering them to the old PDF text field. The native lazy page menu works in the real host, including page 100 and subsequent page navigation. It builds at most 101 items per level and preserves menu item identities during repeated accessibility queries. This is an accessible menu alternative, not text-entry support.
- Native Markdown used a zero-sized text document frame. A viewport/layout-aware scroll view restores the body. Flattened HTML row groups and normalized native table cells produce continuous rows, complete dates and predictable CJK wrapping. Very wide tables scroll horizontally; columns use equal widths.
- Real Finder checks of the original training document confirmed headings/body, table continuity, dates, Chinese wrapping and Preview/Source switching. The original directory name is correct, and hashes of all three files were unchanged during this investigation.
- Dark appearance testing exposed frozen black HTML-import colors. Body runs now use semantic native label colors after import; explicit syntax/link colors remain intact. Light/dark regression checks were added. The user's original Auto appearance setting is restored after GUI testing.

## Automated and integration coverage

Run from a clean source checkout: `Tests/registration.sh`, `Tests/run.sh`, `Tests/archive.sh`, `Tests/pdf.sh`, `Tests/browser.sh`, `build.sh`, `Tests/content.sh`, `Tools/test-renderer.sh`.

The final suite comprises **231 checks**: Registration 11, Analysis 28, Archive 79, PDF 25, Browser 40, Content 20, Renderer 28. No prior check was removed. New lifecycle checks include cancellation before view loading, 20 repeated representable teardowns releasing leases/controllers, and 100 identity-preserving updates. Security, archive limits, scanner cancellation, sorting, columns, inspector, Markdown sanitization and original PDF behavior remain covered.

The main application and both extensions are built and strict deep ad-hoc signature verification is required. Finder testing and automated component tests are distinct: CI cannot establish actual Finder activation, full VoiceOver operation or real cloud-provider behavior. No notarization or Developer ID signing is claimed. Installation follows the tagged source-build workflow; one Folder and one Markdown extension must be registered from Applications.

## Reproducing the investigation

1. Record the installed executable/version and available RAM/OS. Keep private input local.
2. Sample RSS/CPU once per second and take `vmmap -summary` snapshots while active, after Back and after closing Quick Look. Record cumulative CPU time as well as instantaneous ps CPU.
3. Repeat the action sequence above three times with idle periods before reopening. Observe the same process when possible; record process exits/replacements explicitly.
4. Use Instruments Time Profiler (system recording if direct attachment is unavailable) and inspect only the target process. Attempt Allocations/Leaks but disclose attach errors. Run `leaks --noContent` to avoid recording document contents.
5. Retain raw traces locally. Publish sanitized numeric summaries, not private PDFs, document text, raw memory graphs or personal screenshots. Finite successful runs do not certify prolonged stress or every zoom/page combination.

## Remaining limits

The original 5.39 GB event is unexplained and may depend on a different page sequence, zoom level or OS cache state. Native PDFKit recognition and decoding can temporarily consume multiple cores and substantial memory. Long-duration stress, all supported macOS versions, complete VoiceOver use and real cloud providers are not fully verified. No forced cache eviction, decoder replacement, network entitlement or system security bypass was introduced.
