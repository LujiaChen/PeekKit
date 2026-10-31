import Foundation
import Darwin

/// Shared conservative residency guard for explicit previews and directory browsing.
enum LocalFilePolicy {
    static func requireLocal(_ url: URL, directory: Bool = false) throws {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { throw CocoaError(.fileReadNoPermission) }
        let expected = directory ? S_IFDIR : S_IFREG
        guard st.st_mode & S_IFMT == expected else { throw CocoaError(.fileReadUnsupportedScheme) }
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard !FolderAnalyzer.excludesCloud(flags: st.st_flags, isUbiquitous: values.isUbiquitousItem == true, status: values.ubiquitousItemDownloadingStatus) else {
            throw NSError(domain: "PeekKit", code: 12, userInfo: [NSLocalizedDescriptionKey: "This item is not downloaded locally. PeekKit will not download it for preview."])
        }
    }
    static func read(_ url: URL, maximum: Int) throws -> Data {
        try requireLocal(url)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_flags & UInt32(SF_DATALESS) == 0 else { throw CocoaError(.fileReadUnknown) }
        try Task<Never, Never>.checkCancellation()
        return try handle.read(upToCount: maximum) ?? Data()
    }
}
