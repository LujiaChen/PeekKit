import Cocoa
import WebKit

final class RendererSelfTest {
    private let output: URL
    private let controller = PreviewViewController()
    private var window: NSWindow?
    private var results: [String: Any] = [:]
    private var timeout: DispatchWorkItem?
    init(output: URL) { self.output = output }

    func run() {
        let fixture = """
        # Hello Markdown 你好

        **Bold** and *italic* with ~~deleted~~ and [a link](https://example.com).

        ## Details

        | Name | Status |
        | --- | --- |
        | Preview | Ready |

        - [x] Built
        - [ ] Next

        ```swift
        let greeting = "你好"
        ```

        > A useful quotation.

        <script>window.documentInjected = true;</script>
        <img src="https://example.com/tracking.png" onerror="window.documentInjected = true" alt="Remote image">
        <iframe src="https://example.com"></iframe>

        ![Markdown remote image](https://example.com/image.png)

        [bad](javascript:alert(1))
        </script><script>window.documentInjected = true;</script>
        """
        do {
            let native = try nativeMarkdown(fixture)
            results["nativeMarkdown"] = native.string.contains("Hello Markdown 你好") && native.string.contains("Preview") && native.string.contains("Bold")
            let staticHTML = try MarkdownDocument.quickLookHTML(source: fixture, bundle: .main)
            results["quickLookFormatting"] = staticHTML.contains("<h1 id=\"pk-hello-markdown-你好\">Hello Markdown 你好</h1>") && staticHTML.contains("<table>") && staticHTML.contains("<strong>Bold</strong>")
            results["quickLookNoScripts"] = !staticHTML.contains("<script") && !staticHTML.contains("<iframe") && !staticHTML.contains("href=\"javascript:")
            results["quickLookNoNetworkImages"] = !staticHTML.contains("<img src=\"https://") && staticHTML.contains("image not loaded")
            results["quickLookSource"] = staticHTML.contains("<summary>View Markdown source</summary>") && staticHTML.contains("&lt;script&gt;window.documentInjected")
            let fixtureURL = output.deletingLastPathComponent().appendingPathComponent("renderer-test.md")
            try fixture.write(to: fixtureURL, atomically: true, encoding: .utf8)
            let utf16URL = output.deletingLastPathComponent().appendingPathComponent("encoding-test.md")
            try "# 你好 café".write(to: utf16URL, atomically: true, encoding: .utf16)
            results["utf16"] = try MarkdownDocument.read(utf16URL) == "# 你好 café"
            let oversized = output.deletingLastPathComponent().appendingPathComponent("size-test.md")
            try Data(repeating: 65, count: MarkdownDocument.maximumBytes + 1).write(to: oversized)
            do { _ = try MarkdownDocument.read(oversized); results["sizeLimit"] = false }
            catch { results["sizeLimit"] = true }
            try FileManager.default.removeItem(at: oversized)
            window = NSWindow(contentViewController: controller)
            window?.setContentSize(NSSize(width: 840, height: 680))
            let timeout = DispatchWorkItem { [weak self] in self?.finish(error: "Renderer timed out") }
            self.timeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
            var replacedWasCancelled = false
            controller.preparePreviewOfFile(at: fixtureURL) { error in replacedWasCancelled = (error as NSError?)?.code == NSUserCancelledError }
            let cancelledController = PreviewViewController()
            var closedWasCancelled = false
            cancelledController.preparePreviewOfFile(at: fixtureURL) { error in closedWasCancelled = (error as NSError?)?.code == NSUserCancelledError }
            cancelledController.cancelPreparation()
            results["closedPreviewRequestCancelled"] = closedWasCancelled
            controller.preparePreviewOfFile(at: fixtureURL) { [weak self] error in
                guard let self else { return }
                if let error { self.finish(error: error.localizedDescription); return }
                self.results["replacedPreviewRequestCancelled"] = replacedWasCancelled
                self.controller.webView.evaluateJavaScript("""
                (() => {
                  const a = document.getElementById('rendered');
                  const result = {
                    heading: a.querySelector('h1')?.textContent === 'Hello Markdown 你好',
                    bold: a.querySelector('strong')?.textContent === 'Bold',
                    italic: a.querySelector('em')?.textContent === 'italic',
                    strikethrough: a.querySelector('del')?.textContent === 'deleted',
                    table: a.querySelectorAll('td').length === 2,
                    checklist: a.querySelectorAll('input[type=checkbox]').length === 2,
                    code: a.querySelector('pre code')?.textContent.includes('你好'),
                    quote: !!a.querySelector('blockquote'),
                    highlightedCode: !!a.querySelector('pre code .tok-keyword'),
                    tableOfContents: a.querySelectorAll('.toc nav a').length === 2,
                    tocTargetsExist: [...a.querySelectorAll('.toc nav a')].every(link => document.getElementById(decodeURIComponent(link.hash.slice(1)))),
                    documentHTMLInert: !a.querySelector('iframe,script,img[src^="http"]'),
                    safe: !window.documentInjected && !a.querySelector('script,iframe,[onerror],a[href^="javascript:"]'),
                    offline: !a.querySelector('img[src^="http"]') && !!a.querySelector('.image-placeholder'),
                    unicode: document.querySelector('#source code').textContent.includes('你好'),
                    sourceExact: document.querySelector('#source code').textContent.includes('<script>window.documentInjected'),
                  };
                  document.getElementById('source-tab').click();
                  result.sourceTab = a.hidden && !document.getElementById('source').hidden;
                  document.getElementById('preview-tab').click();
                  result.previewTab = !a.hidden && document.getElementById('source').hidden;
                  document.getElementById('larger').click();
                  result.textSize = getComputedStyle(document.documentElement).getPropertyValue('--font-size').trim() === '17px';
                  return result;
                })()
                """) { value, error in
                    if let dictionary = value as? [String: Any] { self.results.merge(dictionary) { _, new in new } }
                    self.finish(error: error?.localizedDescription)
                }
            }
        } catch { finish(error: error.localizedDescription) }
    }

    private func finish(error: String?) {
        timeout?.cancel(); timeout = nil
        if let error { results["error"] = error }
        results["passed"] = error == nil && !results.isEmpty && results.values.allSatisfy { ($0 as? Bool) == true }
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output) }
        NSApp.terminate(nil)
    }
}
