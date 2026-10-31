import AppKit
import SwiftUI

extension PreviewViewController {
    func showError(_ error: Error) {
        let message = error.localizedDescription.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;")
        webView.loadHTMLString("<html><body style='font:16px -apple-system;padding:32px'><h2>Unable to preview Markdown</h2><p>\(message)</p></body></html>",baseURL:nil)
    }
}

struct MarkdownContent: NSViewControllerRepresentable {
    let url: URL
    func makeNSViewController(context: Context) -> PreviewViewController {
        let controller = PreviewViewController()
        controller.preparePreviewOfFile(at: url) { error in
            if let error, (error as NSError).code != NSUserCancelledError { controller.showError(error) }
        }
        return controller
    }
    func updateNSViewController(_ controller: PreviewViewController, context: Context) {}
    static func dismantleNSViewController(_ controller: PreviewViewController, coordinator: ()) { controller.cancelPreparation() }
}


struct NativeMarkdownContent: View {
    let url: URL
    @Environment(\.colorScheme) private var colorScheme
    @State private var source: String?
    @State private var rendered: NSAttributedString?
    @State private var error: String?
    @State private var showSource = false
    var body: some View {
        VStack(spacing:0) {
            Picker("Markdown view",selection:$showSource) { Text("Preview").tag(false); Text("Source").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width:180).padding(12)
            Divider()
            if let source, let rendered {
                NativeMarkdownText(content: showSource ? NSAttributedString(string:source,attributes:[.font:NSFont.monospacedSystemFont(ofSize:13,weight:.regular),.foregroundColor:NSColor.labelColor]) : rendered)
            } else if let error { ContentUnavailableView("Unable to preview Markdown",systemImage:"doc.badge.ellipsis",description:Text(error)) }
            else { Spacer(); ProgressView("Rendering Markdown…"); Spacer() }
        }.task(id: url.path + "|" + String(describing: colorScheme)) {
            source = nil; rendered = nil; error = nil
            let worker = Task.detached(priority: .userInitiated) { () -> (String, String?) in
                let text = try MarkdownDocument.read(url)
                return (text, text.utf8.count <= 128_000 ? try MarkdownDocument.renderBody(source: text, bundle: Bundle(for: PreviewViewController.self)) : nil)
            }
            do {
                let (text, body) = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled else { return }
                if body == nil { rendered = NSAttributedString(string: "Formatted preview limited to 128 KB. Use Source for this document.", attributes: [.foregroundColor: NSColor.labelColor]); source = text }
                else { rendered = try nativeMarkdownBody(body!); source = text }
            }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
func nativeMarkdown(_ source: String) throws -> NSAttributedString {
    return try nativeMarkdownBody(MarkdownDocument.renderBody(source: source, bundle: Bundle(for: PreviewViewController.self)))
}
func nativeMarkdownBody(_ original: String) throws -> NSAttributedString {
    var body = original
    // Native attributed text cannot resolve HTML fragment targets; avoid presenting a dead TOC.
    if body.hasPrefix("<details class=\"toc\">"), let end = body.range(of: "</details>") { body.removeSubrange(body.startIndex..<end.upperBound) }
    let htmlDocument = "<html><head><meta charset='utf-8'><style>body{font:15px -apple-system;color:\(NSColor.labelColor.usingColorSpace(.deviceRGB)!.htmlColor);line-height:1.5}pre,code{font-family:Menlo;font-size:13px}table{border-collapse:collapse}td,th{border:1px solid #b0b0b0;padding:8px}a{color:#2876d7}.tok-keyword{color:#9955bb}.tok-string{color:#328649}.tok-comment{color:#888888}.tok-number{color:#b27822}</style></head><body>\(body)</body></html>"
    return try NSAttributedString(data:Data(htmlDocument.utf8),options:[.documentType:NSAttributedString.DocumentType.html,.characterEncoding:String.Encoding.utf8.rawValue],documentAttributes:nil)
}
extension NSColor {
    var htmlColor: String { String(format:"#%02x%02x%02x",Int(redComponent*255),Int(greenComponent*255),Int(blueComponent*255)) }
}
struct NativeMarkdownText: NSViewRepresentable {
    let content: NSAttributedString
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return true }
            if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            return true
        }
    }
    func makeNSView(context:Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let text = NSTextView(); text.isEditable = false; text.isSelectable = true; text.delegate = context.coordinator; text.drawsBackground = false
        text.textContainerInset = NSSize(width:24,height:20); text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; text.textStorage?.setAttributedString(content)
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) { if let text = scroll.documentView as? NSTextView, text.attributedString() != content { text.textStorage?.setAttributedString(content) } }
}
