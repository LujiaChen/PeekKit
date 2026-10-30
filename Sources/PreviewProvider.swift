import Cocoa
import Quartz
import UniformTypeIdentifiers
import os

@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 840, height: 680)) { reply in
            reply.stringEncoding = .utf8
            let source = try MarkdownDocument.read(url)
            let data = Data(try MarkdownDocument.quickLookHTML(source: source, bundle: Bundle(for: Self.self)).utf8)
            Logger(subsystem: "com.lukechen.peekkit", category: "QuickLook").info("Generated offline HTML preview: \(data.count, privacy: .public) bytes")
            return data
        }
    }
}
