import Cocoa
import Quartz
import WebKit

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private var completion: ((Error?) -> Void)?

    private var preparation: Task<Void, Never>?
    private var requestID = UUID()
    private var activeNavigation: WKNavigation?

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
        preparation?.cancel()
        let id = UUID(); requestID = id
        webView.stopLoading(); activeNavigation = nil
        preparation = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { try MarkdownDocument.html(source: MarkdownDocument.read(url), bundle: Bundle(for: PreviewViewController.self)) }
            do {
                let html = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard let self, self.requestID == id, !Task.isCancelled else { return }
                self.activeNavigation = self.webView.loadHTMLString(html, baseURL: nil)
            } catch { guard let self, self.requestID == id, !Task.isCancelled else { return }; self.finish(error) }
        }
    }
    func cancelPreparation() {
        preparation?.cancel(); requestID = UUID(); activeNavigation = nil; webView?.stopLoading()
        finish(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
    override func viewWillDisappear() { cancelPreparation(); super.viewWillDisappear() }
    deinit { preparation?.cancel() }

    private func finish(_ error: Error?) {
        let callback = completion
        completion = nil
        callback?(error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation else { return }
        let id = requestID
        webView.evaluateJavaScript("window.peekKitReady === true") { [weak self] result, error in
            guard let self, self.requestID == id else { return }
            if let error { self.finish(error) }
            else if result as? Bool == true { self.finish(nil) }
            else { self.finish(NSError(domain: "PeekKit", code: 4, userInfo: [NSLocalizedDescriptionKey: "The Markdown preview could not be rendered."])) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if navigation === activeNavigation { finish(error) } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if navigation === activeNavigation { finish(error) } }
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
