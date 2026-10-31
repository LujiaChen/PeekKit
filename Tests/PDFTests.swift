import AppKit
import PDFKit
import CoreText
import Darwin

@main struct PDFTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath:CommandLine.arguments[1]); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var checks: [String:Bool] = [:]
        func check(_ name:String,_ ok:Bool) { checks[name] = ok; print("\(ok ? "PASS" : "FAIL") \(name)") }
        let url = root.appendingPathComponent("multipage.pdf")
        var rect = CGRect(x:0,y:0,width:612,height:792)
        let context = CGContext(url as CFURL,mediaBox:&rect,nil)!
        for i in 1...40 {
            context.beginPDFPage(nil)
            let text = NSAttributedString(string:"PeekKit synthetic page \(i)",attributes:[.font:NSFont.systemFont(ofSize:26)])
            context.textPosition = CGPoint(x:50,y:650); CTLineDraw(CTLineCreateWithAttributedString(text),context)
            context.endPDFPage()
        }
        context.closePDF()
        let large = root.appendingPathComponent("large-synthetic.pdf")
        try FileManager.default.copyItem(at:url,to:large)
        // Valid incremental PDF update: unreferenced binary stream makes logical size >86 MB.
        let original = try Data(contentsOf:url); let ascii = String(decoding:original,as:UTF8.self)
        let rootRegex = try NSRegularExpression(pattern:#"/Root\s+(\d+)\s+(\d+)\s+R"#)
        let match = rootRegex.firstMatch(in:ascii,range:NSRange(ascii.startIndex...,in:ascii))!
        let rootRef = (1...2).map { String(ascii[Range(match.range(at:$0),in:ascii)!]) }.joined(separator:" ")+" R"
        let previous = ascii.components(separatedBy:"startxref").last!.trimmingCharacters(in:.whitespacesAndNewlines).components(separatedBy:.newlines)[0]
        let handle = try FileHandle(forWritingTo:large); let start = try handle.seekToEnd()
        try handle.write(contentsOf:Data("\n9999 0 obj\n<< /Length 87000000 >>\nstream\n".utf8))
        let dataStart = try handle.offset(); try handle.truncate(atOffset:dataStart+87_000_000); try handle.seek(toOffset:dataStart+87_000_000)
        try handle.write(contentsOf:Data("\nendstream\nendobj\n".utf8)); let xref = try handle.offset()
        let trailer = "xref\n9999 1\n"+String(format:"%010llu 00000 n \n",start)+"trailer\n<< /Size 10000 /Root \(rootRef) /Prev \(previous) >>\nstartxref\n\(xref)\n%%EOF\n"
        try handle.write(contentsOf:Data(trailer.utf8)); try handle.close()
        let began = ProcessInfo.processInfo.systemUptime
        var source: FileBackedPDF? = try FileBackedPDF.load(large)
        let logicalBytes = try large.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        check("largeFileBackedPDF",source?.pageCount == 40 && logicalBytes > 86_000_000)
        let latency = ProcessInfo.processInfo.systemUptime-began
        check("fileBackedDocumentURL",source?.document.documentURL?.path.hasPrefix("/dev/fd/") == true)
        let viewer = PDFViewerController(document:source!.document,source:source); _ = viewer.view
        viewer.view.frame = NSRect(x:0,y:0,width:800,height:600); viewer.view.layoutSubtreeIfNeeded()
        let document = source!.document
        viewer.go(toPage:21)
        check("navigateMultipage",viewer.pdfView.currentPage.map{document.index(for:$0)} == 20)
        let zoom = viewer.pdfView.scaleFactor; viewer.zoomIn()
        check("zoomPDF",viewer.pdfView.scaleFactor > zoom)
        viewer.show(document,source:source)
        check("sameDocumentKeepsPage",viewer.pdfView.currentPage.map{document.index(for:$0)} == 20)
        let other = try FileBackedPDF.load(url); viewer.show(other.document,source:other)
        check("switchDocument",viewer.pdfView.document === other.document)
        viewer.go(toPage:Int.max); check("pageNavigationClamped",viewer.pdfView.currentPage.map{other.document.index(for:$0)} == 39)
        viewer.show(nil); source = nil
        check("dismantleClearsDocument",viewer.pdfView.document == nil)
        let bad = root.appendingPathComponent("corrupt.pdf"); try Data("not a PDF".utf8).write(to:bad)
        for (name,file) in [("corrupt",bad),("missing",root.appendingPathComponent("missing.pdf"))] {
            do { _ = try FileBackedPDF.load(file); check(name+"PDFError",false) } catch { check(name+"PDFError",true) }
        }
        let unreadable = root.appendingPathComponent("unreadable.pdf"); try FileManager.default.copyItem(at:url,to:unreadable); chmod(unreadable.path,0)
        do { _ = try FileBackedPDF.load(unreadable); check("unreadablePDFError",false) } catch { check("unreadablePDFError",true) }; chmod(unreadable.path,0o600)
        check("pdfRecoveryAfterError",try FileBackedPDF.load(url).pageCount == 40)
        let alias = root.appendingPathComponent("link.pdf"); try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:url)
        do { _ = try FileBackedPDF.load(alias); check("symlinkPDFRejected",false) } catch { check("symlinkPDFRejected",true) }
        let locked = root.appendingPathComponent("encrypted.pdf")
        _ = other.document.write(to:locked,withOptions:[PDFDocumentWriteOption.ownerPasswordOption:"owner",PDFDocumentWriteOption.userPasswordOption:"secret"])
        do { _ = try FileBackedPDF.load(locked); check("encryptedPDFError",false) } catch { check("encryptedPDFError",true) }
        let worker = Task.detached { withUnsafeCurrentTask{$0?.cancel()}; return try FileBackedPDF.load(url) }
        do { _ = try await worker.value; check("pdfCancellation",false) } catch is CancellationError { check("pdfCancellation",true) }
        var descriptorsClosed = true
        for _ in 0..<30 {
            autoreleasepool {
                var lease: FileBackedPDF? = try? FileBackedPDF.load(url)
                guard let fd = lease?.descriptor else { descriptorsClosed = false; return }
                var before = stat(); guard fstat(fd,&before) == 0 else { descriptorsClosed = false; return }
                weak var weakLease = lease; lease = nil
                var after = stat(); let valid = fstat(fd,&after) == 0
                // A concurrent framework may reuse a closed descriptor number for another file.
                descriptorsClosed = descriptorsClosed && weakLease == nil && (!valid || after.st_ino != before.st_ino || after.st_dev != before.st_dev)
            }
        }
        check("pdfDescriptorCleanup",descriptorsClosed)
        // The opened inode stays pinned if its original pathname becomes a symlink.
        let pinnedURL = root.appendingPathComponent("pinned.pdf");try FileManager.default.copyItem(at:url,to:pinnedURL)
        let pinned = try FileBackedPDF.load(pinnedURL);try FileManager.default.removeItem(at:pinnedURL)
        try FileManager.default.createSymbolicLink(at:pinnedURL,withDestinationURL:bad)
        check("pinnedInodeAfterReplacement",pinned.document.page(at:39) != nil && pinned.pageCount == 40)
        let report:[String:Any] = ["passed":checks.values.allSatisfy{$0},"checks":checks,"metrics":["largePDFOpenSeconds":latency,"logicalBytes":try large.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0,"pages":40,"note":"Sparse synthetic PDF; not a real-image rendering benchmark"]]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        if checks.values.contains(false) { exit(1) }
    }
}
