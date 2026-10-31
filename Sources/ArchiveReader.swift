import Foundation
import Darwin
import CArchive

struct ArchiveItem: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let directory: Bool
    let size: Int64
    let modified: Date?
    var name: String { (path as NSString).lastPathComponent }
    var parent: String { let p = (path as NSString).deletingLastPathComponent; return p == "." ? "" : p }
}
struct ArchiveListing: Sendable { let items: [ArchiveItem]; let compressedBytes: Int; let format: String }
enum ArchiveReader {
    static let maximumInput = 64 * 1024 * 1024
    static let maximumEntry = 32 * 1024 * 1024
    static let maximumDecoded = 128 * 1024 * 1024
    static func recognizes(_ url: URL) -> Bool { ["zip","tar","tgz","gz","tbz","tbz2","bz2"].contains(url.pathExtension.lowercased()) }
    static func failure(_ message: String) -> NSError { NSError(domain:"PeekKit.Archive",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    static func safePath(_ path: String) throws -> String {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.unicodeScalars.contains(where:{$0.value < 32}), path.utf8.count <= 4096 else { throw failure("Unsafe archive path") }
        let parts = path.split(separator:"/", omittingEmptySubsequences:true).filter{$0 != "."}
        guard !parts.contains(".."), parts.count <= 64 else { throw failure("Unsafe path or nesting limit exceeded") }
        return parts.joined(separator:"/")
    }
    // Restrict ZIP to bounded-memory store/deflate methods before invoking any decoder.
    private static func validateZip(_ data: Data) throws {
        func number(_ at:Int,_ bytes:Int) throws -> Int {
            guard at >= 0, at <= data.count-bytes else { throw failure("Truncated ZIP") }
            return (0..<bytes).reduce(0) { $0 | Int(data[at+$1]) << ($1*8) }
        }
        guard data.count >= 22 else { throw failure("Truncated ZIP") }
        var end: Int?
        for i in stride(from:data.count-22,through:max(0,data.count-65_557),by:-1) {
            if try number(i,4) == 0x06054b50, i+22+(try number(i+20,2)) == data.count { end = i; break }
        }
        guard let end, try number(end+4,4) == 0, try number(end+8,2) == number(end+10,2) else { throw failure("Incomplete or multi-volume ZIP") }
        let count = try number(end+10,2); let length = try number(end+12,4); var offset = try number(end+16,4)
        guard count <= 20_000, offset+length == end else { throw failure("ZIP64 or invalid ZIP directory") }
        for _ in 0..<count {
            guard try number(offset,4) == 0x02014b50 else { throw failure("Invalid ZIP directory") }
            let method = try number(offset+10,2)
            guard method == 0 || method == 8, try number(offset+8,2) & 1 == 0 else { throw failure("Encrypted or unsupported ZIP compression method") }
            offset += 46 + (try number(offset+28,2)) + (try number(offset+30,2)) + (try number(offset+32,2))
            guard offset <= end else { throw failure("Invalid ZIP directory bounds") }
        }
        guard offset == end else { throw failure("Invalid ZIP directory length") }
    }
    static func list(_ url: URL) throws -> ArchiveListing { try process(url, selected:nil).0 }
    static func preview(_ url: URL, path: String) throws -> Data {
        let result = try process(url, selected:path)
        guard let data = result.1 else { throw failure("Archive entry no longer exists") }
        return data
    }
    // Contents are streamed for integrity/resource checks; only the selected entry is retained.
    // No disk extraction, archive path is never used as a filesystem path.
    private static func process(_ url: URL, selected: String?) throws -> (ArchiveListing, Data?) {
        let input = try LocalFilePolicy.read(url, maximum:maximumInput+1)
        guard input.count <= maximumInput else { throw failure("Archive exceeds 64 MiB input limit") }
        if input.starts(with:[0x50,0x4b]) { try validateZip(input) }
        let started = ProcessInfo.processInfo.systemUptime
        func checkpoint() throws {
            try Task<Never,Never>.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime-started < 10 else { throw failure("Archive processing exceeded 10 seconds") }
        }
        return try input.withUnsafeBytes { raw in
            guard let a = archive_read_new() else { throw failure("Archive reader unavailable") }
            defer { archive_read_free(a) }
            archive_read_support_filter_gzip(a); archive_read_support_filter_bzip2(a); /* XZ disabled: decoder has no enforceable memory ceiling. */
            archive_read_support_format_zip(a); archive_read_support_format_tar(a)
            func checked(_ result: Int32) throws {
                guard result == ARCHIVE_OK else { throw failure(archive_error_string(a).map{String(cString:$0)} ?? "Damaged, encrypted or unsupported archive") }
            }
            try checked(archive_read_open_memory(a, raw.baseAddress, raw.count))
            var items: [String:ArchiveItem] = [:]; var explicit: Set<String> = []
            var count = 0; var total = 0; var output: Data?
            var entry: OpaquePointer?
            var buffer = [UInt8](repeating:0,count:64*1024)
            while true {
                try checkpoint()
                let status = archive_read_next_header(a, &entry)
                if status == ARCHIVE_EOF { break }
                try checked(status)
                if archive_format_name(a).map({ String(cString:$0).uppercased().contains("ZIP") }) == true, !input.starts(with:[0x50,0x4b]) { throw failure("Wrapped or self-extracting ZIP is unsupported") }
                guard let entry, let ptr = archive_entry_pathname_utf8(entry), let original = String(validatingUTF8:ptr) else { throw failure("Invalid archive filename encoding") }
                count += 1
                guard count <= 20_000 else { throw failure("Archive exceeds 20,000 entries") }
                let path = try safePath(original)
                let mode = archive_entry_filetype(entry)
                guard archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil, mode == S_IFREG || mode == S_IFDIR else { throw failure("Links and special archive entries are unsupported") }
                guard archive_entry_is_encrypted(entry) == 0 else { throw failure("Encrypted archives are unsupported") }
                let size = archive_entry_size(entry)
                guard size >= 0, size <= maximumEntry else { throw failure("Archive entry exceeds 32 MiB limit") }
                if !path.isEmpty {
                    guard explicit.insert(path).inserted else { throw failure("Duplicate archive path") }
                    let parts = path.split(separator:"/")
                    for depth in 1..<parts.count {
                        let parent = parts.prefix(depth).joined(separator:"/")
                        if let previous = items[parent], !previous.directory { throw failure("Conflicting archive paths") }
                        if items[parent] == nil { items[parent] = ArchiveItem(path:parent,directory:true,size:0,modified:nil) }
                    }
                    if let previous = items[path], previous.directory && mode != S_IFDIR { throw failure("Conflicting archive paths") }
                    items[path] = ArchiveItem(path:path,directory:mode == S_IFDIR,size:size,modified:archive_entry_mtime_is_set(entry) != 0 ? Date(timeIntervalSince1970:Double(archive_entry_mtime(entry))) : nil)
                    guard items.count <= 20_000 else { throw failure("Archive hierarchy exceeds 20,000 nodes") }
                }
                var decoded = 0; var bytes = Data()
                while true {
                    try checkpoint()
                    let read = archive_read_data(a, &buffer, buffer.count)
                    guard read >= 0 else { throw failure("Corrupt or encrypted archive data") }
                    if read == 0 { break }
                    decoded += read; total += read
                    guard decoded <= maximumEntry, total <= maximumDecoded, decoded <= size else { throw failure("Archive decompression limit exceeded") }
                    if path == selected { bytes.append(contentsOf:buffer.prefix(read)) }
                }
                guard mode != S_IFREG || decoded == size else { throw failure("Truncated archive entry") }
                if path == selected { output = bytes }
            }
            return (ArchiveListing(items:Array(items.values),compressedBytes:input.count,format:archive_format_name(a).map{String(cString:$0)} ?? "Archive"), output)
        }
    }
}
