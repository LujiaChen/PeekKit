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
            if let error { controller.showError(error) }
        }
        return controller
    }
    func updateNSViewController(_ controller: PreviewViewController, context: Context) {}
}


struct NativeMarkdownContent: View {
    let url: URL
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
        }.task(id:url) {
            do { let text = try MarkdownDocument.read(url); rendered = try nativeMarkdown(text); source = text }
            catch { self.error = error.localizedDescription }
        }
    }
}
func nativeMarkdown(_ source: String) throws -> NSAttributedString {
    let html = try MarkdownDocument.quickLookHTML(source:source,bundle:Bundle(for:PreviewViewController.self))
    let body = html.components(separatedBy:"<article>").last?.components(separatedBy:"</article>").first ?? ""
    let htmlDocument = "<html><head><meta charset='utf-8'><style>body{font:15px -apple-system;color:\(NSColor.labelColor.usingColorSpace(.deviceRGB)!.htmlColor);line-height:1.5}pre,code{font-family:Menlo;font-size:13px}table{border-collapse:collapse}td,th{border:1px solid #b0b0b0;padding:8px}a{color:#2876d7}</style></head><body>\(body)</body></html>"
    return try NSAttributedString(data:Data(htmlDocument.utf8),options:[.documentType:NSAttributedString.DocumentType.html,.characterEncoding:String.Encoding.utf8.rawValue],documentAttributes:nil)
}
extension NSColor {
    var htmlColor: String { String(format:"#%02x%02x%02x",Int(redComponent*255),Int(greenComponent*255),Int(blueComponent*255)) }
}
struct NativeMarkdownText: NSViewRepresentable {
    let content: NSAttributedString
    func makeNSView(context:Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let text = NSTextView(); text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.textContainerInset = NSSize(width:24,height:20); text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; text.textStorage?.setAttributedString(content)
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) { (scroll.documentView as? NSTextView)?.textStorage?.setAttributedString(content) }
}
