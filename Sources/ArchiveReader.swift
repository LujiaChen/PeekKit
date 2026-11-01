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
    static func recognizes(_ url: URL) -> Bool { ["zip","tar","tgz","gz","tbz","tbz2","bz2","7z"].contains(url.pathExtension.lowercased()) }
    static func failure(_ message: String) -> NSError { NSError(domain:"PeekKit.Archive",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    static func safePath(_ path: String) throws -> String {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.unicodeScalars.contains(where:{$0.value < 32}), path.utf8.count <= 4096 else { throw failure("Unsafe archive path") }
        let parts = path.split(separator:"/", omittingEmptySubsequences:true).filter{$0 != "."}
        guard !parts.contains(".."), parts.count <= 64 else { throw failure("Unsafe path or nesting limit exceeded") }
        return parts.joined(separator:"/")
    }
    private static func integer(_ data: Data, _ at: Int, _ count: Int) throws -> Int {
        guard at >= 0, count <= 8, at <= data.count-count else { throw failure("Invalid archive bounds") }
        return (0..<count).reduce(0) { $0 | Int(data[at+$1]) << ($1*8) }
    }
    // Decompress filters as raw streams: no attacker-controlled TAR metadata is parsed here.
    private static func unpack(_ data: Data, checkpoint: () throws -> Void) throws -> Data {
        guard data.starts(with:[0x1f,0x8b]) || data.starts(with:[0x42,0x5a,0x68]) else { return data }
        return try data.withUnsafeBytes { bytes in
            guard let a = archive_read_new() else { throw failure("Decoder unavailable") }
            defer { archive_read_free(a) }
            archive_read_support_filter_gzip(a); archive_read_support_filter_bzip2(a); archive_read_support_format_raw(a)
            guard archive_read_open_memory(a,bytes.baseAddress,bytes.count) == ARCHIVE_OK else { throw failure("Invalid compressed stream") }
            var entry: OpaquePointer?
            guard archive_filter_count(a) == 2 else { throw failure("Nested compression filters are unsupported") }
            guard archive_read_next_header(a,&entry) == ARCHIVE_OK else { throw failure("Invalid compressed stream") }
            var output = Data(); var buffer = [UInt8](repeating:0,count:65_536)
            while true {
                try checkpoint()
                let count = archive_read_data(a,&buffer,buffer.count)
                guard count >= 0 else { throw failure("Damaged compressed stream") }
                if count == 0 { break }
                guard output.count <= maximumDecoded-count else { throw failure("Expanded TAR exceeds 128 MiB") }
                output.append(contentsOf:buffer.prefix(count))
            }
            guard !output.starts(with:[0x50,0x4b]) else { throw failure("Wrapped ZIP is unsupported") }
            return output
        }
    }
    private static func validateTar(_ data: Data, checkpoint: () throws -> Void) throws {
        var offset = 0; var entries = 0; var metadata = 0
        func octal(_ at:Int,_ length:Int) throws -> Int {
            let bytes = data[at..<at+length].drop(while:{$0 == 0 || $0 == 32}).prefix(while:{$0 != 0 && $0 != 32})
            guard bytes.allSatisfy({$0 >= 48 && $0 <= 55}) else { throw failure("Unsupported TAR numeric encoding") }
            var value = 0
            for byte in bytes { guard value <= maximumDecoded else { throw failure("TAR numeric limit") }; value = value*8+Int(byte-48) }
            return value
        }
        while offset <= data.count-512 {
            try checkpoint()
            if data[offset..<offset+512].allSatisfy({$0 == 0}) {
                guard offset <= data.count-1024, data[offset...].allSatisfy({$0 == 0}) else { throw failure("Truncated TAR terminator") }
                return
            }
            entries += 1; guard entries <= 40_000 else { throw failure("Too many TAR headers") }
            let expected = try octal(offset+148,8)
            let sum = (0..<512).reduce(0) { $0 + ((148..<156).contains($1) ? 32 : Int(data[offset+$1])) }
            guard expected == sum else { throw failure("TAR checksum mismatch") }
            let size = try octal(offset+124,12); let type = data[offset+156]
            guard size <= maximumEntry, [UInt8(0),48,53,120,76].contains(type) else { throw failure("Unsupported TAR entry or size") }
            guard data[offset+157..<offset+257].allSatisfy({$0 == 0}) else { throw failure("TAR links are unsupported") }
            guard offset+512+size <= data.count else { throw failure("Truncated TAR payload") }
            if type == 120 || type == 76 {
                metadata += size
                guard size <= 32_768, metadata <= 2_097_152 else { throw failure("TAR metadata limit") }
                if type == 120 {
                    guard let text = String(data:data.subdata(in:offset+512..<offset+512+size),encoding:.utf8) else { throw failure("Invalid PAX metadata") }
                    // Reject size/link/sparse overrides before libarchive sees them.
                    for line in text.split(separator:"\n") {
                        guard let space = line.firstIndex(of:" "), Int(line[..<space]) == line.utf8.count+1, let equal = line.firstIndex(of:"="), space < equal else { throw failure("Malformed PAX record") }
                        let key = String(line[line.index(after:space)..<equal])
                        guard ["path","mtime","atime","ctime","uid","gid","uname","gname"].contains(key) else { throw failure("Unsupported PAX attribute") }
                    }
                }
            }
            offset += 512+((size+511)/512)*512
        }
        throw failure("Missing TAR terminator")
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
        var spans: [(Int,Int)] = []; var metadata = 0; var decoded = 0
        for _ in 0..<count {
            guard try number(offset,4) == 0x02014b50 else { throw failure("Invalid ZIP directory") }
            let method = try number(offset+10,2)
            guard method == 0 || method == 8, try number(offset+8,2) & 1 == 0 else { throw failure("Encrypted or unsupported ZIP compression method") }
            let flags = try number(offset+8,2)
            let compressed = try number(offset+20,4); let size = try number(offset+24,4)
            let nameLength = try number(offset+28,2); let extraLength = try number(offset+30,2)
            let local = try number(offset+42,4)
            guard nameLength <= 4096, extraLength <= 1024, size <= maximumEntry, compressed <= maximumInput else { throw failure("ZIP metadata/entry limit") }
            metadata += nameLength+extraLength; decoded += size
            guard metadata <= 8_388_608, decoded <= maximumDecoded else { throw failure("ZIP aggregate limit") }
            guard try number(local,4) == 0x04034b50, try number(local+8,2) == method, try number(local+6,2) == flags else { throw failure("ZIP local/central mismatch") }
            let localName = try number(local+26,2); let localExtra = try number(local+28,2)
            if flags & 8 == 0 {
                guard try number(local+18,4) == compressed, try number(local+22,4) == size, try number(local+14,4) == number(offset+16,4) else { throw failure("ZIP size/checksum header mismatch") }
            }
            let start = local+30+localName+localExtra
            guard localName == nameLength, localExtra <= 1024, start <= end-compressed, offset+46+nameLength <= end,
                  data.subdata(in:local+30..<local+30+localName) == data.subdata(in:offset+46..<offset+46+nameLength) else { throw failure("Invalid ZIP local header") }
            // Disallow ZIP64 extras, which could override bounded 32-bit sizes.
            for (base,length) in [(local+30+localName,localExtra),(offset+46+nameLength,extraLength)] {
                var cursor = base
                let extent = base+length
                guard extent <= data.count else { throw failure("Invalid ZIP extra bounds") }
                while cursor < extent {
                    let tag = try number(cursor,2); let fieldLength = try number(cursor+2,2)
                    guard tag != 1, cursor+4+fieldLength <= extent else { throw failure("ZIP64 or malformed extra") }
                    cursor += 4+fieldLength
                }
            }
            spans.append((local,start+compressed))
            offset += 46 + (try number(offset+28,2)) + (try number(offset+30,2)) + (try number(offset+32,2))
            guard offset <= end else { throw failure("Invalid ZIP directory bounds") }
        }
        spans.sort { $0.0 < $1.0 }
        for index in spans.indices { guard spans[index].1 <= (index+1 < spans.count ? spans[index+1].0 : end-length) else { throw failure("Overlapping ZIP entries") } }
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
        let source = try LocalFilePolicy.read(url, maximum:maximumInput+1)
        guard source.count <= maximumInput else { throw failure("Archive exceeds 64 MiB input limit") }
        let started = ProcessInfo.processInfo.systemUptime
        func checkpoint() throws {
            try Task<Never,Never>.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime-started < 10 else { throw failure("Archive processing exceeded 10 seconds") }
        }
        if source.starts(with: SevenZipReader.signature) { return try SevenZipReader.process(source, selected:selected, checkpoint:checkpoint) }
        let input = try unpack(source,checkpoint:checkpoint)
        if input.starts(with:[0x50,0x4b]) { try validateZip(input) } else { try validateTar(input,checkpoint:checkpoint) }
        return try input.withUnsafeBytes { raw in
            guard let a = archive_read_new() else { throw failure("Archive reader unavailable") }
            defer { archive_read_free(a) }
            // Filters already removed under a decoded-byte budget; parse only plain ZIP/TAR.
            archive_read_support_format_zip(a); archive_read_support_format_tar(a)
            func checked(_ result: Int32) throws {
                guard result == ARCHIVE_OK else { throw failure(archive_error_string(a).map{String(cString:$0)} ?? "Damaged, encrypted or unsupported archive") }
            }
            try checked(archive_read_open_memory(a, raw.baseAddress, raw.count))
            var items: [String:ArchiveItem] = [:]; var explicit: Set<String> = []
            var count = 0; var total = 0; var namesBytes = 0; var output: Data?
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
                namesBytes += path.utf8.count
                guard namesBytes <= 4_194_304 else { throw failure("Archive path metadata exceeds 4 MiB") }
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
            return (ArchiveListing(items:Array(items.values),compressedBytes:source.count,format:archive_format_name(a).map{String(cString:$0)} ?? "Archive"), output)
        }
    }
}
