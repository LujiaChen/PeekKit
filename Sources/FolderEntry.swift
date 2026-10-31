import Foundation

struct FolderEntry: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    let isFolder: Bool
    let isLink: Bool
    let size: Int64
    let modified: Date?
    let kind: String
    static func read(_ folder: URL, showHidden: Bool, limit: Int = 20_000) throws -> ([FolderEntry], Bool) {
        try LocalFilePolicy.requireLocal(folder, directory: true)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey]
        var enumerationError: Error?
        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]
        if !showHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: options, errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw CocoaError(.fileReadNoPermission) }
        var entries: [FolderEntry] = []
        var truncated = false
        while let url = enumerator.nextObject() as? URL {
            try Task<Never, Never>.checkCancellation()
            if entries.count == limit { truncated = true; break }
            let v = try? url.resourceValues(forKeys: keys)
            entries.append(FolderEntry(url: url, name: url.lastPathComponent, isFolder: v?.isDirectory == true && v?.isPackage != true && v?.isSymbolicLink != true, isLink: v?.isSymbolicLink == true, size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate, kind: v?.localizedTypeDescription ?? "File"))
        }
        if let enumerationError { throw enumerationError }
        return (entries, truncated)
    }
}

enum FolderOrdering {
    static func sorted(_ entries: [FolderEntry], by sort: String) -> [FolderEntry] {
        entries.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            switch sort {
            case "Size": if a.size != b.size { return a.size > b.size }
            case "Modified": if a.modified != b.modified { return (a.modified ?? .distantPast) > (b.modified ?? .distantPast) }
            case "Type": if a.kind != b.kind { return a.kind.localizedStandardCompare(b.kind) == .orderedAscending }
            default: break
            }
            let order = a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? a.url.path < b.url.path : order == .orderedAscending
        }
    }
}
