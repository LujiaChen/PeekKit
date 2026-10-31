import AppKit
import PDFKit
import UniformTypeIdentifiers

enum PreviewPayload {
    case markdown, image(CGImage), pdf(PDFDocument), text(String), unsupported
    static func load(_ url: URL) throws -> PreviewPayload {
        try LocalFilePolicy.requireLocal(url)
        try Task<Never, Never>.checkCancellation()
        let v = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let size = v.fileSize ?? 0
        if isMarkdown(url) { return .markdown }
        if v.contentType?.conforms(to: .image) == true, size < 50_000_000, let cg = imageThumbnail(url, pixels: 1800) { return .image(cg) }
        if v.contentType?.conforms(to: .pdf) == true, size < 50_000_000 {
            let data = try LocalFilePolicy.read(url, maximum: 50_000_001)
            if data.count <= 50_000_000, let document = PDFDocument(data: data) { return .pdf(document) }
        }
        if v.contentType?.conforms(to: .text) == true || ["json","yaml","yml","swift","py","js","ts","csv","log","sh"].contains(url.pathExtension.lowercased()) {
            let data = try LocalFilePolicy.read(url, maximum: 128_001)
            let prefix = Data(data.prefix(128_000))
            var decoded: String?
            if prefix.starts(with: [0xff, 0xfe]) || prefix.starts(with: [0xfe, 0xff]) { decoded = String(data: prefix.prefix(prefix.count - prefix.count % 2), encoding: .utf16) }
            else {
                for trim in 0...min(3, prefix.count) {
                    if let value = String(data: prefix.dropLast(trim), encoding: .utf8) { decoded = value; break }
                }
            }
            if let text = decoded { return .text(text + (data.count > 128_000 ? "\n\n… Preview limited to the first 128 KB." : "")) }
        }
        return .unsupported
    }
}

struct EntryActions: SwiftUI.View {
    let url: URL
    var body: some SwiftUI.View {
        SwiftUI.Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        SwiftUI.Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
        SwiftUI.Button("Open in Default App") { NSWorkspace.shared.open(url) }
        SwiftUI.Button("Open With…") {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.prompt = "Choose App"
            if panel.runModal() == .OK, let app = panel.url { NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) }
        }
    }
}
import SwiftUI
