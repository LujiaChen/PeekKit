import Foundation
import ImageIO
import PDFKit
import Darwin
import UniformTypeIdentifiers

/// Reads filesystem metadata without opening file contents or following symlinks.
struct PeekKitInspection: Sendable {
    let path: String
    let name: String
    let fileExtension: String
    let type: String?
    let logicalBytes: Int64
    let allocatedBytes: Int64
    let created: Date
    let modified: Date
    let accessed: Date
    let permissions: String
    let isSymlink: Bool
    var pixelDimensions: String? = nil
    var pdfPages: Int? = nil

    static func read(_ url: URL) throws -> PeekKitInspection {
        try Task<Never, Never>.checkCancellation()
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let isLink = info.st_mode & S_IFMT == S_IFLNK
        let blocks = max(0, Int64(info.st_blocks)).multipliedReportingOverflow(by: 512)
        let type = isLink || url.pathExtension.isEmpty ? nil : UTType(filenameExtension: url.pathExtension)?.identifier
        try Task<Never, Never>.checkCancellation()
        var result = PeekKitInspection(path: url.path, name: url.lastPathComponent,
                              fileExtension: url.pathExtension, type: type,
                              logicalBytes: max(0, info.st_size),
                              allocatedBytes: blocks.overflow ? .max : blocks.partialValue,
                              created: Date(timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec)),
                              modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)),
                              accessed: Date(timeIntervalSince1970: Double(info.st_atimespec.tv_sec)),
                              permissions: String(format: "%04o", Int(info.st_mode & 0o7777)),
                              isSymlink: isLink)
        if !isLink, info.st_size <= 8_000_000, ["png","jpg","jpeg","tif","tiff","gif","pdf"].contains(url.pathExtension.lowercased()),
           let data = try? LocalFilePolicy.read(url, maximum:8_000_001), data.count <= 8_000_000 {
            if url.pathExtension.lowercased() == "pdf" { result.pdfPages = PDFDocument(data:data)?.pageCount }
            else if let source = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
                    let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
                    let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int { result.pixelDimensions = "\(width) × \(height)" }
        }
        try Task<Never,Never>.checkCancellation()
        return result
    }
}
