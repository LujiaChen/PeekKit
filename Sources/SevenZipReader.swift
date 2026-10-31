import Foundation
import CLzma

/// Deliberately narrow 7z parser. Untrusted 7z headers never enter libarchive's
/// general 7z parser. Only a validated single raw Copy/LZMA1/LZMA2 coder reaches
/// liblzma, with bounded properties, decoder memory estimate and output buffer.
enum SevenZipReader {
    static let signature: [UInt8] = [0x37,0x7a,0xbc,0xaf,0x27,0x1c]
    static let headerLimit = 1024 * 1024
    static let dictionaryLimit = 8 * 1024 * 1024
    private static func fail(_ message: String) -> NSError { ArchiveReader.failure("7z: " + message) }
    private struct Cursor {
        let data: Data
        var at = 0
        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, at <= data.count - count else { throw fail("truncated header") }
            defer { at += count }; return data.subdata(in: at..<at+count)
        }
        mutating func byte() throws -> UInt8 { guard at < data.count else { throw fail("truncated header") }; defer { at += 1 }; return data[at] }
        mutating func expect(_ value: UInt8) throws { guard try byte() == value else { throw fail("unsupported header structure") } }
        mutating func uint(_ maximum: Int = ArchiveReader.maximumDecoded) throws -> Int {
            let first = try byte(); var mask: UInt8 = 0x80; var value: UInt64 = 0
            for i in 0..<8 {
                if first & mask == 0 { value |= UInt64(first & (mask - 1)) << (8*i); guard value <= UInt64(maximum) else { throw fail("numeric/resource limit") }; return Int(value) }
                value |= UInt64(try byte()) << (8*i); mask >>= 1
            }
            guard value <= UInt64(maximum) else { throw fail("numeric/resource limit") }; return Int(value)
        }
        mutating func real(_ count: Int) throws -> UInt64 { try bytes(count).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8*$1.offset) } }
        mutating func bits(_ count: Int) throws -> [Bool] {
            let b = try bytes((count+7)/8); return (0..<count).map { b[$0/8] & (0x80 >> ($0%8)) != 0 }
        }
        mutating func defined(_ count: Int) throws -> [Bool] {
            let all = try byte(); guard all <= 1 else { throw fail("invalid definition flags") }; return all == 1 ? [Bool](repeating: true, count: count) : try bits(count)
        }
        mutating func digests(_ count: Int) throws -> [UInt32?] {
            let flags = try defined(count); return try flags.map { $0 ? UInt32(try real(4)) : nil }
        }
        var done: Bool { at == data.count }
    }
    private struct Coder { let method: Data; let properties: Data }
    private struct Streams {
        var packPosition = 0
        var packed: [Int] = []
        var packCRC: [UInt32?] = []
        var coders: [Coder] = []
        var unpacked: [Int] = []
        var folderCRC: [UInt32?] = []
        var sizes: [[Int]] = []
        var crc: [[UInt32?]] = []
    }
    private struct Files {
        var names: [String] = []
        var empty: [Bool] = []
        var emptyFile: [Bool] = []
        var attributes: [UInt32?] = []
        var modified: [Date?] = []
    }
    private static let crcTable: [UInt32] = (0..<256).map { n in
        var v = UInt32(n); for _ in 0..<8 { v = (v & 1) == 1 ? (v >> 1) ^ 0xedb88320 : v >> 1 }; return v
    }
    static func crc32(_ data: Data) -> UInt32 { var crc = UInt32.max; for b in data { crc = crcTable[Int((crc ^ UInt32(b)) & 255)] ^ (crc >> 8) }; return ~crc }
    private static func validate(_ coder: Coder) throws {
        let p = coder.properties
        if coder.method == Data([0]) { guard p.isEmpty else { throw fail("Copy properties") }; return }
        if coder.method == Data([0x03,0x01,0x01]) {
            guard p.count == 5, p[0] < 225 else { throw fail("invalid LZMA1 properties") }
            let lc = Int(p[0]) % 9, lp = (Int(p[0])/9) % 5
            let dictionary = (1..<5).reduce(UInt64(0)) { $0 | UInt64(p[$1]) << (8*($1-1)) }
            guard lc+lp <= 4, dictionary <= dictionaryLimit else { throw fail("LZMA1 dictionary/probability limit (8 MiB)") }
            return
        }
        if coder.method == Data([0x21]) {
            guard p.count == 1, p[0] <= 22 else { throw fail("LZMA2 dictionary limit (8 MiB)") }; return
        }
        throw fail("unsupported codec, filter chain or encryption; supported: Copy, LZMA1, LZMA2")
    }
    private static func streams(_ c: inout Cursor, outputLimit: Int, checkpoint: () throws -> Void) throws -> Streams {
        var s = Streams()
        try c.expect(6); s.packPosition = try c.uint(ArchiveReader.maximumInput)
        let count = try c.uint(20_000); guard count > 0 else { throw fail("empty stream table") }
        try c.expect(9); for _ in 0..<count { s.packed.append(try c.uint(ArchiveReader.maximumInput)) }
        var id = try c.byte(); s.packCRC = [UInt32?](repeating:nil,count:count)
        if id == 10 { s.packCRC = try c.digests(count); id = try c.byte() }
        guard id == 0 else { throw fail("unsupported PackInfo") }
        try c.expect(7); try c.expect(11)
        let folders = try c.uint(20_000); guard folders == count else { throw fail("one packed stream per folder required") }
        try c.expect(0) // no external coder metadata
        for _ in 0..<folders {
            try checkpoint(); guard try c.uint(64) == 1 else { throw fail("only one coder per folder is supported; filter chains/encrypted archives are unsupported") }
            let flags = try c.byte(), length = Int(flags & 15)
            guard length > 0, length <= 4, flags & 0xd0 == 0 else { throw fail("complex/filter-chain coders are unsupported") }
            let method = try c.bytes(length)
            guard [Data([0]), Data([0x03,0x01,0x01]), Data([0x21])].contains(method) else { throw fail("unsupported codec/filter chain or encrypted archive") }
            let properties = flags & 0x20 != 0 ? try c.bytes(c.uint(5)) : Data()
            let coder = Coder(method:method,properties:properties); try validate(coder); s.coders.append(coder)
        }
        try c.expect(12)
        var total = 0
        for _ in 0..<folders { let size = try c.uint(outputLimit); total += size; guard total <= outputLimit else { throw fail("aggregate decoded stream limit") }; s.unpacked.append(size) }
        s.folderCRC = [UInt32?](repeating:nil,count:folders); id = try c.byte()
        if id == 10 { s.folderCRC = try c.digests(folders); id = try c.byte() }
        guard id == 0 else { throw fail("unsupported UnPackInfo") }
        var counts = [Int](repeating:1,count:folders); var subSizes = [[Int]](repeating:[],count:folders)
        id = try c.byte()
        if id == 8 {
            id = try c.byte()
            if id == 13 { counts = []; var n = 0; for _ in 0..<folders { let value = try c.uint(20_000); n += value; guard value > 0, n <= 20_000 else { throw fail("substream count limit") }; counts.append(value) }; id = try c.byte() }
            if id == 9 {
                for f in 0..<folders { var sum = 0; for _ in 0..<counts[f]-1 { let value = try c.uint(ArchiveReader.maximumEntry); sum += value; guard sum <= s.unpacked[f] else { throw fail("substream size mismatch") }; subSizes[f].append(value) } }
                id = try c.byte()
            } else if counts.contains(where:{$0 != 1}) { throw fail("missing substream sizes") }
            let digestCount = (0..<folders).reduce(0) { $0 + ((counts[$1] == 1 && s.folderCRC[$1] != nil) ? 0 : counts[$1]) }
            var digests = [UInt32?](repeating:nil,count:digestCount)
            if id == 10 { digests = try c.digests(digestCount); id = try c.byte() }
            guard id == 0 else { throw fail("unsupported SubStreamsInfo") }
            var index = 0
            for f in 0..<folders {
                if counts[f] == 1, let crc = s.folderCRC[f] { s.crc.append([crc]) }
                else { s.crc.append(Array(digests[index..<index+counts[f]])); index += counts[f] }
            }
            id = try c.byte()
        } else { s.crc = s.folderCRC.map { [$0] } }
        guard id == 0 else { throw fail("unsupported stream metadata") }
        for f in 0..<folders {
            let remainder = s.unpacked[f] - subSizes[f].reduce(0,+)
            guard remainder <= ArchiveReader.maximumEntry else { throw fail("entry exceeds 32 MiB") }
            subSizes[f].append(remainder)
            guard subSizes[f].count == counts[f] else { throw fail("substream count mismatch") }
        }
        s.sizes = subSizes; return s
    }
    private static func files(_ c: inout Cursor) throws -> Files {
        let count = try c.uint(20_000); var f = Files()
        f.empty = [Bool](repeating:false,count:count); f.attributes = [UInt32?](repeating:nil,count:count); f.modified = [Date?](repeating:nil,count:count)
        var seen = Set<UInt8>()
        while true {
            let id = try c.byte(); if id == 0 { break }
            guard id == 25 || seen.insert(id).inserted else { throw fail("duplicate file property") }
            let size = try c.uint(headerLimit); var p = Cursor(data:try c.bytes(size))
            switch id {
            case 14: f.empty = try p.bits(count)
            case 15: f.emptyFile = try p.bits(f.empty.filter{$0}.count)
            case 16: guard try p.bits(f.empty.filter{$0}.count).allSatisfy({!$0}) else { throw fail("anti-files are unsupported") }
            case 17:
                try p.expect(0); let names = try p.bytes(size-1)
                guard names.count % 2 == 0 else { throw fail("invalid UTF-16 names") }
                var start = 0
                for i in stride(from:0,to:names.count,by:2) where names[i] == 0 && names[i+1] == 0 {
                    let bytes = names.subdata(in:start..<i)
                    guard let name = String(data:bytes,encoding:.utf16LittleEndian), name.data(using:.utf16LittleEndian) == bytes else { throw fail("invalid filename encoding") }
                    f.names.append(name); start = i+2
                }
                guard start == names.count, f.names.count == count else { throw fail("filename count mismatch") }
            case 18,19,20,21:
                let defined = try p.defined(count); try p.expect(0)
                for i in 0..<count where defined[i] {
                    if id == 21 { f.attributes[i] = UInt32(try p.real(4)) }
                    else { let ticks = try p.real(8); if id == 20 { f.modified[i] = Date(timeIntervalSince1970: Double(ticks)/10_000_000 - 11_644_473_600) } }
                }
            case 25: guard try p.bytes(size).allSatisfy({$0 == 0}) else { throw fail("nonzero padding") }
            default: throw fail("unsupported/external file metadata")
            }
            guard p.done else { throw fail("file property size mismatch") }
        }
        guard f.names.count == count else { throw fail("missing filenames") }
        if f.emptyFile.isEmpty { f.emptyFile = [Bool](repeating:false,count:f.empty.filter{$0}.count) }
        return f
    }
    private static func decode(_ source: Data, _ s: Streams, end: Int, checkpoint: () throws -> Void) throws -> ([Data], Range<Int>) {
        var offset = 32+s.packPosition; let start = offset; var output: [Data] = []
        for i in s.coders.indices {
            try checkpoint(); let count = s.packed[i]
            guard offset <= end-count else { throw fail("packed stream outside data area") }
            let input = source.subdata(in:offset..<offset+count); offset += count
            if let crc = s.packCRC[i], crc32(input) != crc { throw fail("packed checksum mismatch") }
            let coder = s.coders[i]; try validate(coder)
            var data: Data
            if coder.method == Data([0]) { guard input.count == s.unpacked[i] else { throw fail("Copy size mismatch") }; data = input }
            else {
                data = Data(count:s.unpacked[i])
                let result = data.withUnsafeMutableBytes { out in input.withUnsafeBytes { src in coder.properties.withUnsafeBytes { props in
                    peek_lzma_decode(coder.method == Data([0x21]) ? 1 : 0, props.bindMemory(to:UInt8.self).baseAddress, props.count, src.bindMemory(to:UInt8.self).baseAddress, src.count, out.bindMemory(to:UInt8.self).baseAddress, out.count)
                } } }
                guard result == 0 else { throw fail("damaged or unsupported LZMA stream") }
            }
            try checkpoint()
            if let crc = s.folderCRC[i], crc32(data) != crc { throw fail("decoded checksum mismatch") }
            output.append(data)
        }
        return (output,start..<offset)
    }
    static func process(_ source: Data, selected: String?, checkpoint: () throws -> Void) throws -> (ArchiveListing,Data?) {
        var start = Cursor(data:source)
        guard try start.bytes(6) == Data(signature), try start.byte() == 0 else { throw fail("invalid signature/version") }
        _ = try start.byte(); let crc = UInt32(try start.real(4))
        guard crc32(try start.bytes(20)) == crc else { throw fail("start-header checksum mismatch") }
        var fields = Cursor(data:source.subdata(in:12..<32))
        let offset = try fields.real(8), size = try fields.real(8), headerCRC = UInt32(try fields.real(4))
        guard offset <= source.count-32, size <= headerLimit, size == source.count-32-Int(offset) else { throw fail("header bounds/1 MiB metadata limit") }
        let end = 32+Int(offset); let header = source.subdata(in:end..<source.count)
        guard crc32(header) == headerCRC else { throw fail("next-header checksum mismatch") }
        var c = Cursor(data:header); var encodedRange: Range<Int>?
        if header.first == 23 {
            try c.expect(23); let s = try streams(&c,outputLimit:headerLimit,checkpoint:checkpoint)
            guard c.done, s.coders.count == 1, s.sizes[0].count == 1 else { throw fail("unsupported encoded header") }
            let decoded = try decode(source,s,end:end,checkpoint:checkpoint); encodedRange = decoded.1; c = Cursor(data:decoded.0[0])
        }
        if c.done { return (ArchiveListing(items:[],compressedBytes:source.count,format:"7z"),nil) }
        try c.expect(1); var id = try c.byte(); var s: Streams?
        if id == 4 { s = try streams(&c,outputLimit:ArchiveReader.maximumDecoded,checkpoint:checkpoint); id = try c.byte() }
        var f = Files()
        if id == 5 { f = try files(&c); id = try c.byte() }
        guard id == 0, c.done else { throw fail("unsupported/extra header sections") }
        let sizes = s?.sizes.flatMap{$0} ?? [], digests = s?.crc.flatMap{$0} ?? []
        guard f.empty.filter({!$0}).count == sizes.count else { throw fail("file/stream count mismatch") }
        var items: [String:ArchiveItem] = [:]; var explicit = Set<String>(); var streamIndex = 0, emptyIndex = 0
        var filePaths: [String] = []
        for i in f.names.indices {
            try checkpoint(); let path = try ArchiveReader.safePath(f.names[i]); guard !path.isEmpty, explicit.insert(path).inserted else { throw fail("empty/duplicate path") }
            let directory = f.empty[i] && !f.emptyFile[emptyIndex]
            if f.empty[i] { emptyIndex += 1 }
            if let attr = f.attributes[i] {
                let mode = (attr >> 16) & 0xf000
                guard attr & 0x400 == 0, (attr & 0x8000 == 0 || mode == 0 || mode == (directory ? 0x4000 : 0x8000)), (attr & 0x10 != 0) == directory else { throw fail("links/special or inconsistent attributes") }
            }
            let size = f.empty[i] ? 0 : sizes[streamIndex]
            if !f.empty[i] { filePaths.append(path); streamIndex += 1 }
            let parts = path.split(separator:"/")
            for depth in 1..<parts.count {
                let parent = parts.prefix(depth).joined(separator:"/")
                if let previous = items[parent], !previous.directory { throw fail("conflicting paths") }
                if items[parent] == nil { items[parent] = ArchiveItem(path:parent,directory:true,size:0,modified:nil) }
            }
            if let previous = items[path], previous.directory && !directory { throw fail("conflicting paths") }
            items[path] = ArchiveItem(path:path,directory:directory,size:Int64(size),modified:f.modified[i])
            guard items.count <= 20_000 else { throw fail("hierarchy node limit") }
        }
        var result: Data?
        if let s {
            let decoded = try decode(source,s,end:end,checkpoint:checkpoint)
            if let range = encodedRange, range.overlaps(decoded.1) { throw fail("overlapping header/data streams") }
            var index = 0
            for (folder, data) in decoded.0.enumerated() {
                var position = 0
                for size in s.sizes[folder] {
                    try checkpoint(); let bytes = data.subdata(in:position..<position+size); position += size
                    if let crc = digests[index], crc32(bytes) != crc { throw fail("file checksum mismatch") }
                    if filePaths[index] == selected { result = bytes }; index += 1
                }
            }
        }
        return (ArchiveListing(items:Array(items.values),compressedBytes:source.count,format:"7z (Copy/LZMA1/LZMA2)"),result)
    }
}
