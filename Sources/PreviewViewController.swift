import Cocoa
import Quartz
import WebKit

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private var completion: ((Error?) -> Void)?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 840, height: 680), configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsLinkPreview = false
        webView.setValue(false, forKey: "drawsBackground")
        view = webView
        preferredContentSize = NSSize(width: 840, height: 680)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        _ = view
        completion?(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        completion = handler
        do {
            let html = try MarkdownDocument.html(source: MarkdownDocument.read(url), bundle: Bundle(for: Self.self))
            webView.loadHTMLString(html, baseURL: nil)
        } catch {
            finish(error)
        }
    }

    private func finish(_ error: Error?) {
        let callback = completion
        completion = nil
        callback?(error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.peekKitReady === true") { [weak self] result, error in
            if let error { self?.finish(error) }
            else if result as? Bool == true { self?.finish(nil) }
            else { self?.finish(NSError(domain: "PeekKit", code: 4, userInfo: [NSLocalizedDescriptionKey: "The Markdown preview could not be rendered."])) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(NSError(domain: "PeekKit", code: 5, userInfo: [NSLocalizedDescriptionKey: "The preview process stopped. Close Quick Look and press Space to try again."]))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated {
            if let url = action.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        } else {
            decisionHandler(action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }
}
