import Foundation
import Darwin
@main struct ArchiveTests {
    static func main() async throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1]); var checks:[String:Bool] = [:]
        func check(_ name:String,_ value:Bool) { checks[name] = value; print("\(value ? "PASS" : "FAIL") \(name)") }
        for format in ["zip","tar","tar.gz","tar.bz2"] {
            let file = root.appendingPathComponent("valid."+format)
            let list = try ArchiveReader.list(file)
            check(format+"Hierarchy",list.items.contains{$0.path == "nested/你好.txt" && $0.size == 5} && list.items.contains{$0.path == "nested" && $0.directory})
            check(format+"Preview",try ArchiveReader.preview(file,path:"nested/你好.txt") == Data("hello".utf8))
        }
        for name in ["traversal.tar","symlink.tar","hardlink.tar","fifo.tar","absolute.zip","duplicate.zip","deep.tar","huge.tar","corrupt.zip","truncated.zip","encrypted.zip","oversize.zip","many.tar","bomb.zip","valid.tar.xz","localmethod.zip","crc.zip","truncated.tar","truncated.tgz","metadata.tar","headerbomb.tgz","checksum.tar","conflict.tar"] {
            do { _ = try ArchiveReader.list(root.appendingPathComponent(name)); check(name+"Rejected",false) } catch { check(name+"Rejected",true) }
        }
        check("emptyZip",try ArchiveReader.list(root.appendingPathComponent("empty.zip")).items.isEmpty)
        let worker = Task.detached { withUnsafeCurrentTask{$0?.cancel()}; return try ArchiveReader.list(root.appendingPathComponent("valid.tar")) }
        do { _ = try await worker.value; check("cancellation",false) } catch is CancellationError { check("cancellation",true) }
        check("emptyTar", try ArchiveReader.list(root.appendingPathComponent("empty.tar")).items.isEmpty)
        let started = ProcessInfo.processInfo.systemUptime
        let large = try ArchiveReader.list(root.appendingPathComponent("large.tar"))
        let largeSeconds = ProcessInfo.processInfo.systemUptime-started
        check("largeTar",large.items.count == 5001)
        let zipStart = ProcessInfo.processInfo.systemUptime
        check("largeZipPreview",try ArchiveReader.preview(root.appendingPathComponent("large.zip"),path:"large.txt").count == 8*1024*1024)
        let zipSeconds = ProcessInfo.processInfo.systemUptime-zipStart
        let repeatedStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<20 { _ = try ArchiveReader.preview(root.appendingPathComponent("valid.zip"),path:"nested/你好.txt") }
        let repeatedSeconds = ProcessInfo.processInfo.systemUptime-repeatedStart
        let active = Task.detached { try ArchiveReader.list(root.appendingPathComponent("large.tar")) }
        try await Task.sleep(nanoseconds:1_000_000)
        let cancelStart = ProcessInfo.processInfo.systemUptime; active.cancel()
        do { _ = try await active.value; check("activeCancellation",false) } catch is CancellationError { check("activeCancellation",true) }
        let cancellationSeconds = ProcessInfo.processInfo.systemUptime-cancelStart
        var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
        let metrics:[String:Any] = ["largeZip8MiBSeconds":zipSeconds,"largeTar5000Seconds":largeSeconds,"twentyZipPreviewsSeconds":repeatedSeconds,"cancellationSeconds":cancellationSeconds,"peakRSSBytes":usage.ru_maxrss,"os":ProcessInfo.processInfo.operatingSystemVersionString,"processors":ProcessInfo.processInfo.processorCount]
        let report:[String:Any] = ["passed":checks.values.allSatisfy{$0},"checks":checks,"metrics":metrics]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        if !checks.values.allSatisfy({$0}) { exit(1) }
    }
}
