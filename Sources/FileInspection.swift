import Foundation
import Darwin

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

    static func read(_ url: URL) throws -> PeekKitInspection {
        try Task<Never, Never>.checkCancellation()
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let isLink = info.st_mode & S_IFMT == S_IFLNK
        let blocks = max(0, Int64(info.st_blocks)).multipliedReportingOverflow(by: 512)
        let type = isLink ? nil : (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier)
        try Task<Never, Never>.checkCancellation()
        return PeekKitInspection(path: url.path, name: url.lastPathComponent,
                              fileExtension: url.pathExtension, type: type,
                              logicalBytes: max(0, info.st_size),
                              allocatedBytes: blocks.overflow ? .max : blocks.partialValue,
                              created: Date(timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec)),
                              modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)),
                              accessed: Date(timeIntervalSince1970: Double(info.st_atimespec.tv_sec)),
                              permissions: String(format: "%04o", Int(info.st_mode & 0o7777)),
                              isSymlink: isLink)
    }
}
