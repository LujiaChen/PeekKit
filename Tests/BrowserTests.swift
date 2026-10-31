import Foundation
import SwiftUI
import ImageIO
import Darwin

@main struct BrowserTests {
    @MainActor static func main() async throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1]); let fm = FileManager.default
        try fm.createDirectory(at: base.appendingPathComponent("sub/deep"), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: base.appendingPathComponent("sub/a.txt"))
        try Data("# Heading".utf8).write(to: base.appendingPathComponent("readme.md"))
        try Data([0xff,0xfe]).write(to: base.appendingPathComponent("bad.txt"))
        let alias = base.appendingPathComponent("alias"); try fm.createSymbolicLink(at: alias, withDestinationURL: base.appendingPathComponent("sub"))
        let suite = "PeekKit.Tests." + UUID().uuidString; let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ value: Bool) { checks[name] = value; print("\(value ? "PASS" : "FAIL") \(name)") }
        func settle(_ condition: @MainActor () -> Bool) async throws { for _ in 0..<500 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) } }
        let model = FolderModel(root: base, preferences: prefs); model.load()
        try await settle { !model.loading && model.visible.count == 4 }
        check("initialListingAndFolderFirst", model.visible.count == 4 && model.visible.first?.name == "sub")
        let folder = model.entries.first { $0.name == "sub" }!
        model.mode = "Tree"; model.toggle(folder)
        try await settle { model.treeRows.contains { $0.entry.name == "a.txt" } }
        check("treeExpansion", model.treeRows.contains { $0.entry.name == "a.txt" && $0.depth == 1 })
        let rootBefore = model.analysis.snapshot?.root
        model.query = "a.txt"; try await settle { model.treeRows.count == 2 }
        check("treeFilterKeepsAncestor", model.treeRows.map(\.entry.name) == ["sub", "a.txt"])
        check("filterDoesNotRestartAnalysis", model.analysis.snapshot?.root == rootBefore && model.current == base)
        model.query = ""; model.toggle(folder); try await settle { !model.treeRows.contains { $0.entry.name == "a.txt" } }
        check("treeCollapse", !model.expanded.contains(folder.url))
        model.toggle(folder); model.toggle(folder); model.load(base.appendingPathComponent("sub/deep"))
        try await settle { !model.loading }
        try await Task.sleep(nanoseconds: 100_000_000)
        check("navigationRejectsStaleTreeResults", model.treeRows.isEmpty && model.current.lastPathComponent == "deep")
        model.back(); try await settle { !model.loading && model.visible.count == 2 }
        check("backNavigation", model.current.lastPathComponent == "sub")
        model.load(URL(fileURLWithPath: "/tmp")); check("navigationCannotEscapeRoot", model.current.lastPathComponent == "sub")
        model.load(base); try await settle { !model.loading && model.visible.count == 4 }
        model.mode = "List"; model.moveFocus(.down); check("keyboardFocus", model.focused == model.visible.first?.url)
        model.openFocused(); try await settle { !model.loading }; check("keyboardOpenFolder", model.current == folder.url)
        model.mode = "Tree"; model.sort = "Type"
        let restored = FolderModel(root: base, preferences: prefs)
        check("viewPreferencesPersist", restored.mode == "Tree" && restored.sort == "Type")
        let sample = [FolderEntry(url:base.appendingPathComponent("z"), name:"z", isFolder:false,isLink:false,size:7,modified:Date(timeIntervalSince1970:2),kind:"Text"), FolderEntry(url:base.appendingPathComponent("a"),name:"a",isFolder:false,isLink:false,size:9,modified:Date(timeIntervalSince1970:1),kind:"Archive")]
        check("sortSize", FolderOrdering.sorted(sample, by:"Size").first?.name == "a")
        check("sortModified", FolderOrdering.sorted(sample, by:"Modified").first?.name == "z")
        check("sortType", FolderOrdering.sorted(sample, by:"Type").first?.name == "a")
        check("sortName", FolderOrdering.sorted(sample, by:"Name").first?.name == "a")
        do { try LocalFilePolicy.requireLocal(alias, directory:true); check("previewRejectsSymlink",false) } catch { check("previewRejectsSymlink",true) }
        do { _ = try PreviewPayload.load(base.appendingPathComponent("bad.txt")); check("malformedTextDoesNotCrash",true) } catch { check("malformedTextDoesNotCrash",true) }
        let wide = base.appendingPathComponent("wide.txt")
        try String(repeating: "你", count: 50_000).write(to: wide, atomically:true, encoding:.utf8)
        if case .text(let value) = try PreviewPayload.load(wide) { check("utf8BoundaryPreview",value.contains("Preview limited") && value.hasPrefix("你")) } else { check("utf8BoundaryPreview",false) }
        let utf16 = base.appendingPathComponent("utf16.txt");try "你好 café".write(to:utf16,atomically:true,encoding:.utf16)
        if case .text(let value) = try PreviewPayload.load(utf16) { check("utf16TextPreview",value=="你好 café") } else { check("utf16TextPreview",false) }
        let denied = base.appendingPathComponent("Denied");try fm.createDirectory(at:denied,withIntermediateDirectories:true);try fm.setAttributes([.posixPermissions:0],ofItemAtPath:denied.path)
        model.load(base);try await settle { !model.loading && model.entries.contains { $0.name=="Denied" } }
        if let entry=model.entries.first(where:{$0.name=="Denied"}) {
            model.toggle(entry);try await settle { model.treeMessages[entry.url] != nil && model.treeMessages[entry.url] != "Loading…" }
            check("treePermissionError",model.treeMessages[entry.url] != nil && model.treeMessages[entry.url] != "Loading…")
        } else {check("treePermissionError",false)}
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:denied.path)
        let png = base.appendingPathComponent("pixel.png")
        let bitmap = CGContext(data:nil,width:2,height:2,bitsPerComponent:8,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));bitmap.fill(CGRect(x:0,y:0,width:2,height:2))
        let destination = CGImageDestinationCreateWithURL(png as CFURL,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,bitmap.makeImage()!,nil);let written=CGImageDestinationFinalize(destination)
        if case .image(let image)=try PreviewPayload.load(png) {check("imagePreviewDecode",written && image.width==2 && image.height==2)}else{check("imagePreviewDecode",false)}
        let pdfURL = base.appendingPathComponent("page.pdf");var rect=CGRect(x:0,y:0,width:100,height:100)
        let pdfContext=CGContext(pdfURL as CFURL,mediaBox:&rect,nil)!
        pdfContext.beginPDFPage(nil);pdfContext.fill(rect);pdfContext.endPDFPage();pdfContext.closePDF()
        if case .pdf(let document)=try PreviewPayload.load(pdfURL) {check("pdfPreviewDecode",document.pageCount==1)}else{check("pdfPreviewDecode",false)}
        let inspection = try PeekKitInspection.read(wide)
        var statInfo = stat(); let statOK = lstat(wide.path, &statInfo) == 0
        check("inspectorMetadata", statOK && inspection.name == "wide.txt" && inspection.fileExtension == "txt" && inspection.logicalBytes == 150_000 && inspection.allocatedBytes == Int64(statInfo.st_blocks) * 512 && inspection.permissions == String(format:"%04o", Int(statInfo.st_mode & 0o7777)))
        let linkInspection = try PeekKitInspection.read(alias)
        check("inspectorDoesNotFollowSymlink", linkInspection.isSymlink && linkInspection.type == nil)
        do { _ = try PeekKitInspection.read(base.appendingPathComponent("missing")); check("inspectorMissingFile",false) } catch { check("inspectorMissingFile",true) }
        check("markdownDetection", isMarkdown(base.appendingPathComponent("x.MD")))
        model.load(base); model.dispose(); let before = model.entries.count
        try await Task.sleep(nanoseconds:100_000_000)
        check("disposeRejectsLateListing", model.entries.count == before)
        var weakOwner: FolderModel? = FolderModel(root:base, preferences:prefs); weak var released: FolderModel?; released = weakOwner
        weakOwner?.load(); weakOwner = nil; try await Task.sleep(nanoseconds:100_000_000)
        check("closedBrowserModelReleased", released == nil)
        // Reproducible rendering benchmark: same 20,000 synthetic entries, 20 reads.
        let many = (0..<20_000).map { i in FolderEntry(url:base.appendingPathComponent(String(i)), name:"File \(20_000-i).txt",isFolder:false,isLink:false,size:Int64(i),modified:nil,kind:"Text") }
        let benchmarkModel = FolderModel(root:base, preferences:prefs);benchmarkModel.entries = many
        try await settle { benchmarkModel.visible.count == many.count }
        let start=ProcessInfo.processInfo.systemUptime;var sum=0
        for _ in 0..<20 { sum += FolderOrdering.sorted(many,by:"Name").count }
        let legacy=ProcessInfo.processInfo.systemUptime-start
        let cachedStart=ProcessInfo.processInfo.systemUptime
        for _ in 0..<20 { sum += benchmarkModel.visible.count }
        let cached=ProcessInfo.processInfo.systemUptime-cachedStart
        check("cachedPresentationCount", sum==800_000)
        let report:[String:Any] = ["passed":checks.values.allSatisfy{$0},"checks":checks,"benchmark":["entries":20000,"reads":20,"legacyRepeatedSortSeconds":legacy,"cachedPresentationReadSeconds":cached]]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        benchmarkModel.dispose();model.dispose();restored.dispose()
        if !checks.values.allSatisfy({$0}) { exit(1) }
    }
}
