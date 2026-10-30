import Foundation
import Darwin

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var counts: [Int] = []
    func record(_ value: Int) { lock.lock(); counts.append(value); lock.unlock() }
}

@main struct FolderAnalysisTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        var results: [String: Bool] = [:]
        var measurements: [String: Double] = [:]
        func check(_ name: String, _ success: Bool) { results[name] = success; print("\(success ? "PASS" : "FAIL") \(name)") }
        func folder(_ path: String) throws -> URL {
            let url = base.appendingPathComponent(path)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func file(_ path: String, _ size: Int) throws -> URL {
            let url = base.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 65, count: size).write(to: url)
            return url
        }
        func diskBytes(_ paths: [URL]) -> Int64 { paths.reduce(0) { n, url in var st = stat(); _ = lstat(url.path, &st); return n + Int64(st.st_blocks) * 512 } }
        func scan(_ root: URL, _ options: FolderAnalysisOptions = FolderAnalysisOptions(), token: AnalysisCancellation = AnalysisCancellation()) -> FolderAnalysisSnapshot {
            FolderAnalyzer.scan(root: root, options: options, cancellation: token)
        }
        let nested = try folder("Nested")
        let a = try file("Nested/a.txt", 100)
        let b = try file("Nested/sub/b.txt", 200)
        let large = try file("Nested/sub/deep/large.bin", 131072)
        let package = try file("Nested/Demo.app/Contents/local.dat", 512)
        let noExtension = try file("Nested/README", 30)
        let sparse = try file("Nested/sparse.dat", 0)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.seek(toOffset: 4_194_304); try handle.write(contentsOf: Data([1]))
        var hole = fpunchhole_t(fp_flags: 0, reserved: 0, fp_offset: 0, fp_length: 4_194_304)
        let sparseResult = fcntl(handle.fileDescriptor, F_PUNCHHOLE, &hole)
        try handle.synchronize(); try handle.close()
        check("sparseFixtureHasUnallocatedHole", sparseResult == 0 && diskBytes([sparse]) < 4_194_305)
        _ = try file("Nested/.secret", 50)
        _ = try file("Nested/.hidden/x.dat", 60)
        let outside = try file("Outside/ignore.bin", 1_000_000)
        _ = link(a.path, nested.appendingPathComponent("a-hard.txt").path)
        _ = symlink(nested.path, nested.appendingPathComponent("loop").path)
        _ = symlink(outside.path, nested.appendingPathComponent("outside-link").path)
        _ = mkfifo(nested.appendingPathComponent("fifo").path, 0o600)
        let basic = scan(nested)
        let expected: Int64 = 100 + 200 + 131072 + 512 + 30 + 4194305
        check("nestedRecursiveTotal", basic.logicalBytes == expected && basic.fileCount == 6 && basic.state == .complete)
        check("allocatedBlocksAndSparseFile", basic.allocatedBytes == diskBytes([a,b,large,package,noExtension,sparse]) && basic.logicalBytes > basic.allocatedBytes)
        check("packageContentsIncluded", basic.largestLogical.contains { $0.relativePath == "Demo.app/Contents/local.dat" })
        check("extensionCountsAndSizes", basic.types.first { $0.name == ".txt" }?.count == 2 && basic.types.first { $0.name == ".txt" }?.logicalBytes == 300)
        check("distributionAddsToTotal", basic.types.reduce(0) { $0 + $1.logicalBytes } == expected && basic.types.reduce(0) { $0 + $1.count } == 6)
        check("symlinksAndFIFOAreNotFollowed", basic.symbolicLinksSkipped == 2 && basic.otherItemsSkipped == 1 && basic.fileCount == 6)
        check("hardLinksCountOnce", basic.hardLinksSkipped == 1)
        check("largestRankedByLogicalOrAllocated", basic.largestLogical.first?.relativePath == "sparse.dat" && basic.largestAllocated.first?.relativePath == "sub/deep/large.bin")
        check("hiddenSubtreeExcluded", basic.hiddenEntriesSkipped == 2)
        var allOptions = FolderAnalysisOptions(); allOptions.includeHidden = true
        let all = scan(nested, allOptions)
        check("hiddenScopeCanBeIncluded", all.logicalBytes == expected + 110 && all.fileCount == 8)
        let empty = scan(try folder("Empty"))
        check("emptyDirectory", empty.fileCount == 0 && empty.logicalBytes == 0 && empty.state == .complete && !empty.isPartial)
        let denied = try folder("Denied")
        let lockedDirectory = try folder("Denied/private")
        _ = try file("Denied/private/secret.txt", 77)
        let lockedFile = try file("Denied/no-access.txt", 88)
        _ = try file("Denied/readable.txt", 9)
        chmod(lockedDirectory.path, 0); chmod(lockedFile.path, 0)
        let partial = scan(denied)
        chmod(lockedDirectory.path, 0o700); chmod(lockedFile.path, 0o600)
        check("permissionFailuresArePartialAndReported", partial.unreadableItems == 2 && partial.fileCount == 1 && partial.logicalBytes == 9 && partial.isPartial && partial.issues.count == 2)
        check("unreadableRoot", scan(base.appendingPathComponent("Missing")).unreadableItems == 1)
        check("symbolicLinkRootRejected", scan(nested.appendingPathComponent("loop")).unreadableItems == 1)
        check("cloudPolicyNoDownload", FolderAnalyzer.excludesCloud(flags:UInt32(SF_DATALESS),isUbiquitous:false,status:nil) && FolderAnalyzer.excludesCloud(flags:0,isUbiquitous:true,status:.notDownloaded) && FolderAnalyzer.excludesCloud(flags:0,isUbiquitous:true,status:nil) && !FolderAnalyzer.excludesCloud(flags:0,isUbiquitous:true,status:.downloaded) && !FolderAnalyzer.excludesCloud(flags:0,isUbiquitous:true,status:.current))
        var depthOptions = FolderAnalysisOptions(); depthOptions.maximumDepth = 1
        let depth = scan(nested, depthOptions)
        check("depthLimitIsExplicit", depth.state == .limited && !depth.limitReasons.isEmpty && depth.isPartial)
        var countOptions = FolderAnalysisOptions(); countOptions.maximumEntries = 3
        check("entryLimitIsExplicit", scan(nested, countOptions).state == .limited)
        var timeOptions = FolderAnalysisOptions(); timeOptions.maximumSeconds = 0
        check("timeLimitIsExplicit", scan(nested, timeOptions).state == .limited)
        let many = try folder("Large")
        for index in 0..<25_000 { _ = fm.createFile(atPath: many.appendingPathComponent(String(format:"%05d.txt",index)).path, contents:Data()) }
        let recorder = ProgressRecorder()
        var manyOptions = FolderAnalysisOptions(); manyOptions.updateInterval = 0.001
        let start = Date()
        let manyResult = await Task.detached { FolderAnalyzer.scan(root:many,options:manyOptions,cancellation:AnalysisCancellation()) { recorder.record($0.visitedEntries) } }.value
        measurements["largeScanSeconds"] = Date().timeIntervalSince(start)
        check("largeDirectoryNotCappedAtBrowserLimit", manyResult.fileCount == 25_000 && manyResult.state == .complete && manyResult.largestLogical.count == 20)
        check("incrementalProgress", recorder.counts.count > 2 && recorder.counts.first == 0 && recorder.counts.last == manyResult.visitedEntries)
        let cancel = AnalysisCancellation()
        let stopped = await Task.detached { FolderAnalyzer.scan(root:many,options:manyOptions,cancellation:cancel) { if $0.visitedEntries >= 500 { cancel.cancel() } } }.value
        check("cancelStopsBeforeFinishing", stopped.state == .stopped && stopped.visitedEntries < 25_000)
        let beforeFDs = (try? fm.contentsOfDirectory(atPath:"/dev/fd").count) ?? 0
        for _ in 0..<20 { let token=AnalysisCancellation();token.cancel();_ = scan(many, token:token) }
        let afterFDs = (try? fm.contentsOfDirectory(atPath:"/dev/fd").count) ?? 0
        check("cancellationClosesDirectoryDescriptors", afterFDs <= beforeFDs + 1)
        let model = FolderAnalysisModel()
        model.start(root:many,includeHidden:false)
        model.start(root:base.appendingPathComponent("Empty"),includeHidden:false)
        for _ in 0..<200 {
            if model.snapshot?.state != .scanning { break }
            try await Task.sleep(nanoseconds:10_000_000)
        }
        check("navigationDiscardsOldScanUpdates", model.snapshot?.root.lastPathComponent == "Empty" && model.snapshot?.fileCount == 0 && model.snapshot?.state == .complete)
        model.start(root:many,includeHidden:false)
        var heartbeatCount = 0
        var maximumHeartbeatDelay = 0.0
        var lastHeartbeat = ProcessInfo.processInfo.systemUptime
        while model.snapshot?.state == .scanning && heartbeatCount < 200 {
            try await Task.sleep(nanoseconds:10_000_000)
            let now = ProcessInfo.processInfo.systemUptime
            maximumHeartbeatDelay = max(maximumHeartbeatDelay, now - lastHeartbeat)
            lastHeartbeat = now; heartbeatCount += 1
        }
        measurements["maximumMainActorHeartbeatDelaySeconds"] = maximumHeartbeatDelay
        check("mainActorRemainsResponsiveDuringScan", heartbeatCount > 5 && maximumHeartbeatDelay < 0.25)
        model.start(root:many,includeHidden:false)
        model.stop()
        for _ in 0..<200 {
            if model.snapshot?.state != .scanning { break }
            try await Task.sleep(nanoseconds:10_000_000)
        }
        check("modelStopCompletes", model.snapshot?.state == .stopped)
        model.start(root:many,includeHidden:false)
        model.cancel()
        let value = model.snapshot?.visitedEntries
        try await Task.sleep(nanoseconds:100_000_000)
        check("previewCloseCancelsAndRejectsLateUpdates", model.snapshot?.visitedEntries == value)
        var weakModel: FolderAnalysisModel?
        weak var released: FolderAnalysisModel?
        weakModel = FolderAnalysisModel();released=weakModel
        weakModel?.start(root:many,includeHidden:false);weakModel=nil
        try await Task.sleep(nanoseconds:100_000_000)
        check("workerDoesNotRetainClosedPreviewModel", released == nil)
        let report: [String:Any] = ["passed":results.values.allSatisfy{$0},"checks":results,"measurements":measurements,"cloudTesting":"Policy tested deterministically; no real cloud placeholder was hydrated."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        if !results.values.allSatisfy({$0}) { exit(1) }
    }
}
