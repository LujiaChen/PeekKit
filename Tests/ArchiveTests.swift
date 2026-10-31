import Foundation
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
        for name in ["traversal.tar","symlink.tar","hardlink.tar","fifo.tar","absolute.zip","duplicate.zip","deep.tar","huge.tar","corrupt.zip","truncated.zip","encrypted.zip","oversize.zip","many.tar","bomb.zip","valid.tar.xz"] {
            do { _ = try ArchiveReader.list(root.appendingPathComponent(name)); check(name+"Rejected",false) } catch { check(name+"Rejected",true) }
        }
        check("emptyZip",try ArchiveReader.list(root.appendingPathComponent("empty.zip")).items.isEmpty)
        let worker = Task.detached { withUnsafeCurrentTask{$0?.cancel()}; return try ArchiveReader.list(root.appendingPathComponent("valid.tar")) }
        do { _ = try await worker.value; check("cancellation",false) } catch is CancellationError { check("cancellation",true) }
        let report:[String:Any] = ["passed":checks.values.allSatisfy{$0},"checks":checks]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        if !checks.values.allSatisfy({$0}) { exit(1) }
    }
}
