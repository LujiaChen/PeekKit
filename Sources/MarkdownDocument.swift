import Foundation
import JavaScriptCore

enum MarkdownDocument {
    static let maximumBytes = 8 * 1024 * 1024

    static func read(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else {
            throw NSError(domain: "PeekKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file is larger than 8 MB. Open it in your editor to read it."])
        }
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]),
           let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .utf8) { return text.replacingOccurrences(of: "\u{feff}", with: "") }
        throw NSError(domain: "PeekKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "This file is not UTF-8 or UTF-16 text. Save it as UTF-8 in your editor and try again."])
    }

    static func html(source: String, bundle: Bundle) throws -> String {
        func resource(_ name: String, _ ext: String) throws -> String {
            guard let url = bundle.url(forResource: name, withExtension: ext) else {
                throw NSError(domain: "PeekKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "A preview resource is missing: \(name).\(ext)"])
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
        let nonce = UUID().uuidString
        let payload = Data(source.utf8).base64EncodedString()
        return try resource("preview", "html")
            .replacingOccurrences(of: "__NONCE__", with: nonce)
            .replacingOccurrences(of: "__CSS__", with: resource("preview", "css"))
            .replacingOccurrences(of: "__LIBRARIES__", with: resource("marked", "js") + "\n" + resource("purify", "js"))
            .replacingOccurrences(of: "__PAYLOAD__", with: payload)
            .replacingOccurrences(of: "__RENDERER__", with: resource("preview", "js"))
    }

    static func quickLookHTML(source: String, bundle: Bundle) throws -> String {
        guard let library = bundle.url(forResource: "marked", withExtension: "js"),
              let stylesheet = bundle.url(forResource: "preview", withExtension: "css"),
              let renderer = bundle.url(forResource: "static-renderer", withExtension: "js"),
              let context = JSContext() else { throw NSError(domain: "PeekKit", code: 6) }
        var scriptError: String?
        context.exceptionHandler = { _, exception in scriptError = exception?.toString() }
        context.evaluateScript(try String(contentsOf: library, encoding: .utf8))
        context.evaluateScript(try String(contentsOf: renderer, encoding: .utf8))
        guard let body = context.objectForKeyedSubscript("renderMarkdownSafely")?.call(withArguments: [source])?.toString(), scriptError == nil else {
            throw NSError(domain: "PeekKit", code: 7, userInfo: [NSLocalizedDescriptionKey: scriptError ?? "Could not render Markdown"])
        }
        let css = try String(contentsOf: stylesheet, encoding: .utf8)
        let escaped = source.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'">
        <style>\(css) details{font-size:12px;color:var(--muted);margin-bottom:26px}summary{cursor:pointer}details pre{margin-top:14px;max-height:50vh;overflow:auto}article{margin-top:20px}</style>
        </head><body><main><details><summary>View Markdown source</summary><pre>\(escaped)</pre></details><article>\(body.isEmpty ? "<p id=empty>This Markdown file is empty.</p>" : body)</article></main></body></html>
        """
    }
}
