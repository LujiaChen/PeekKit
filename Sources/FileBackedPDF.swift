import Foundation
import PDFKit
import Darwin

/// Keeps the no-follow descriptor alive for PDFKit's deferred page reads.
/// /dev/fd pins the opened inode, so replacing the original path with a symlink
/// cannot redirect subsequent reads. No whole-file Data or page rasterization.
final class FileBackedPDF {
    let document: PDFDocument
    private let handle: FileHandle
    var pageCount: Int { document.pageCount }
    static func load(_ url: URL) throws -> FileBackedPDF {
        try LocalFilePolicy.requireLocal(url)
        try Task<Never, Never>.checkCancellation()
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw failure("The PDF cannot be opened. Check that it exists and is readable.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            var st = stat()
            guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_flags & UInt32(SF_DATALESS) == 0 else { throw failure("The PDF is not a local regular file. Download it explicitly before previewing.") }
            guard let document = PDFDocument(url: URL(fileURLWithPath: "/dev/fd/\(fd)")) else { throw failure("This PDF is damaged or is not a valid PDF document.") }
            try Task<Never, Never>.checkCancellation()
            guard !document.isLocked else { throw failure("This PDF is password protected. Open it in Preview to unlock it.") }
            guard document.pageCount > 0 else { throw failure("This PDF has no readable pages.") }
            return FileBackedPDF(document: document, handle: handle)
        } catch { try? handle.close(); throw error }
    }
    private init(document: PDFDocument, handle: FileHandle) { self.document = document; self.handle = handle }
    deinit { try? handle.close() }
    private static func failure(_ message: String) -> NSError { NSError(domain: "PeekKit.PDF", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
