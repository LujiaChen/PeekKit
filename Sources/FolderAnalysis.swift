import Foundation
import Darwin

// Independent metadata-only scanner. No file-content reads, downloads or network APIs.
struct FolderAnalysisOptions: Sendable {
    var includeHidden = false
    var maximumEntries = 1_000_000
    var maximumDepth = 128
    var maximumSeconds: Double = 60
    var largestFileLimit = 20
    var maximumTypes = 256
    var updateInterval: Double = 0.25
}

final class AnalysisCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

enum AnalysisState: String, Codable, Sendable { case scanning, complete, stopped, limited }
enum AnalysisMetric: String, CaseIterable, Sendable { case logical = "Size", allocated = "On disk" }

struct AnalyzedFile: Identifiable, Sendable {
    var id: String { relativePath }
    let url: URL
    let relativePath: String
    let logicalBytes: Int64
    let allocatedBytes: Int64
    var isDirectory = false
    var partial = false
    var fileCount = 0
    func bytes(_ metric: AnalysisMetric) -> Int64 { metric == .logical ? logicalBytes : allocatedBytes }
}
struct AnalyzedType: Identifiable, Sendable {
    var id: String { name }
    let name: String
    var count = 0
    var logicalBytes: Int64 = 0
    var allocatedBytes: Int64 = 0
    func bytes(_ metric: AnalysisMetric) -> Int64 { metric == .logical ? logicalBytes : allocatedBytes }
}
struct AnalysisIssue: Identifiable, Sendable {
    var id: String { path + message }
    let path: String
    let message: String
}
struct FolderAnalysisSnapshot: Sendable {
    let root: URL
    var state: AnalysisState = .scanning
    var includeHidden = false
    var visitedEntries = 0
    var fileCount = 0
    var folderCount = 0
    var logicalBytes: Int64 = 0
    var allocatedBytes: Int64 = 0
    var hiddenEntriesSkipped = 0
    var symbolicLinksSkipped = 0
    var cloudItemsSkipped = 0
    var unreadableItems = 0
    var otherItemsSkipped = 0
    var hardLinksSkipped = 0
    var otherVolumesSkipped = 0
    var unknownCloudMetadata = 0
    var limitReasons: [String] = []
    var issues: [AnalysisIssue] = []
    var types: [AnalyzedType] = []
    var largestLogical: [AnalyzedFile] = []
    var largestAllocated: [AnalyzedFile] = []
    var largestLogicalFolders: [AnalyzedFile] = []
    var largestAllocatedFolders: [AnalyzedFile] = []
    var elapsedSeconds: Double = 0
    var isPartial: Bool {
        state != .complete || unreadableItems > 0 || cloudItemsSkipped > 0 || otherVolumesSkipped > 0 || unknownCloudMetadata > 0
    }
    func largest(_ metric: AnalysisMetric) -> [AnalyzedFile] { metric == .logical ? largestLogical : largestAllocated }
    func largestFolders(_ metric: AnalysisMetric) -> [AnalyzedFile] { metric == .logical ? largestLogicalFolders : largestAllocatedFolders }
    func sortedTypes(_ metric: AnalysisMetric) -> [AnalyzedType] {
        types.sorted { $0.bytes(metric) == $1.bytes(metric) ? $0.name < $1.name : $0.bytes(metric) > $1.bytes(metric) }
    }
}

private struct FileIdentity: Hashable { let device: dev_t; let inode: ino_t }
private final class ScanDirectory {
    let stream: UnsafeMutablePointer<DIR>
    let url: URL
    let relative: String
    let depth: Int
    var logical: Int64 = 0
    var allocated: Int64 = 0
    var files = 0
    var partial = false
    init(stream: UnsafeMutablePointer<DIR>, url: URL, relative: String, depth: Int) {
        self.stream = stream; self.url = url; self.relative = relative; self.depth = depth
    }
    deinit { closedir(stream) }
}

enum FolderAnalyzer {
    static func addingBytes(_ lhs: Int64, _ rhs: Int64) -> (value: Int64, overflow: Bool) {
        let sum = lhs.addingReportingOverflow(rhs)
        return (sum.overflow ? Int64.max : sum.partialValue, sum.overflow)
    }
    // Used by both the actual metadata reader and deterministic cloud-policy tests.
    static func excludesCloud(flags: UInt32, isUbiquitous: Bool, status: URLUbiquitousItemDownloadingStatus?) -> Bool {
        flags & UInt32(SF_DATALESS) != 0 || (isUbiquitous && status != .current && status != .downloaded)
    }

    static func scan(root: URL, options: FolderAnalysisOptions, cancellation: AnalysisCancellation,
                     progress: @Sendable (FolderAnalysisSnapshot) -> Void = { _ in }) -> FolderAnalysisSnapshot {
        let began = ProcessInfo.processInfo.systemUptime
        var result = FolderAnalysisSnapshot(root: root, includeHidden: options.includeHidden)
        var buckets: [String: AnalyzedType] = [:]
        var hardLinks = Set<FileIdentity>()
        var stack: [ScanDirectory] = []
        var lastEmission = began
        var rootDevice: dev_t = 0
        var forceLimited = false
        var byteOverflow = false

        func issue(_ relative: String, _ message: String) {
            stack.last?.partial = true
            result.unreadableItems += 1
            if result.issues.count < 16 { result.issues.append(AnalysisIssue(path: relative.isEmpty ? "." : relative, message: message)) }
        }
        func limit(_ message: String) {
            if !result.limitReasons.contains(message) { result.limitReasons.append(message) }
            forceLimited = true
            stack.last?.partial = true
        }
        func snapshot() -> FolderAnalysisSnapshot {
            var copy = result
            copy.types = Array(buckets.values)
            copy.elapsedSeconds = ProcessInfo.processInfo.systemUptime - began
            return copy
        }
        func emitIfNeeded(force: Bool = false) {
            let now = ProcessInfo.processInfo.systemUptime
            if force || now - lastEmission >= options.updateInterval {
                progress(snapshot()); lastEmission = now
            }
        }
        func add(_ value: Int64, to total: inout Int64) {
            let sum = addingBytes(total, value)
            total = sum.value
            if sum.overflow { byteOverflow = true; stack.last?.partial = true }
        }
        func cloudExcluded(_ url: URL, flags: UInt32, relative: String) -> Bool {
            if flags & UInt32(SF_DATALESS) != 0 { result.cloudItemsSkipped += 1; stack.last?.partial = true; return true }
            do {
                let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                if excludesCloud(flags: flags, isUbiquitous: values.isUbiquitousItem == true, status: values.ubiquitousItemDownloadingStatus) {
                    result.cloudItemsSkipped += 1; stack.last?.partial = true; return true
                }
            } catch {
                // Be conservative if cloud residency cannot be established; never open contents to find out.
                stack.last?.partial = true
                result.unknownCloudMetadata += 1
                if result.issues.count < 16 { result.issues.append(AnalysisIssue(path: relative, message: "Residency metadata unavailable; skipped: " + error.localizedDescription)) }
                return true
            }
            return false
        }
        func insert(_ file: AnalyzedFile, into list: inout [AnalyzedFile], metric: AnalysisMetric) {
            guard options.largestFileLimit > 0 else { return }
            if list.count == options.largestFileLimit, let tail = list.last,
               file.bytes(metric) < tail.bytes(metric) { return }
            let index = list.firstIndex { old in
                file.bytes(metric) > old.bytes(metric) || (file.bytes(metric) == old.bytes(metric) && file.relativePath < old.relativePath)
            } ?? list.endIndex
            list.insert(file, at: index)
            if list.count > options.largestFileLimit { list.removeLast() }
        }

        func closeDirectory(partial: Bool = false) {
            let directory = stack.removeLast()
            directory.partial = directory.partial || partial
            if let parent = stack.last {
                add(directory.logical, to: &parent.logical); add(directory.allocated, to: &parent.allocated)
                parent.files += directory.files; parent.partial = parent.partial || directory.partial
                let folder = AnalyzedFile(url: directory.url, relativePath: directory.relative, logicalBytes: directory.logical, allocatedBytes: directory.allocated, isDirectory: true, partial: directory.partial, fileCount: directory.files)
                insert(folder, into: &result.largestLogicalFolders, metric: .logical)
                insert(folder, into: &result.largestAllocatedFolders, metric: .allocated)
            }
        }

        progress(result)
        if cancellation.isCancelled || Task<Never, Never>.isCancelled {
            result.state = .stopped
            progress(result)
            return result
        }
        var rootStat = stat()
        if lstat(root.path, &rootStat) != 0 {
            issue(".", String(cString: strerror(errno)))
        } else if rootStat.st_mode & S_IFMT != S_IFDIR {
            issue(".", "The analysis root must be a directory, not a symbolic link or file.")
        } else if !cloudExcluded(root, flags: rootStat.st_flags, relative: ".") {
            rootDevice = rootStat.st_dev
            let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            if fd < 0 { issue(".", String(cString: strerror(errno))) }
            else {
                var actual = stat()
                if fstat(fd, &actual) != 0 || actual.st_dev != rootStat.st_dev || actual.st_ino != rootStat.st_ino {
                    close(fd); issue(".", "Root directory changed before enumeration; skipped.")
                } else if let stream = fdopendir(fd) {
                    stack.append(ScanDirectory(stream: stream, url: root, relative: "", depth: 0))
                } else { let code = errno; close(fd); issue(".", String(cString: strerror(code))) }
            }
        }

        while let directory = stack.last {
            if cancellation.isCancelled || Task<Never, Never>.isCancelled { break }
            if result.visitedEntries >= options.maximumEntries { limit("Stopped at \(options.maximumEntries) entries. Analyze a smaller subfolder for full coverage."); break }
            if ProcessInfo.processInfo.systemUptime - began >= options.maximumSeconds { limit("Stopped after \(Int(options.maximumSeconds)) seconds. Analyze a smaller subfolder for full coverage."); break }
            errno = 0
            guard let entry = readdir(directory.stream) else {
                let code = errno
                if code != 0 { issue(directory.relative, String(cString: strerror(code))) }
                closeDirectory(); continue
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            result.visitedEntries += 1
            emitIfNeeded()
            let relative = directory.relative.isEmpty ? name : directory.relative + "/" + name
            let fd = dirfd(directory.stream)
            var info = stat()
            guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { issue(relative, String(cString: strerror(errno))); continue }
            let hidden = name.hasPrefix(".") || info.st_flags & UInt32(UF_HIDDEN) != 0
            if hidden && !options.includeHidden { result.hiddenEntriesSkipped += 1; continue }
            let mode = info.st_mode & S_IFMT
            if mode == S_IFLNK { result.symbolicLinksSkipped += 1; continue }
            if info.st_dev != rootDevice { result.otherVolumesSkipped += 1; directory.partial = true; continue }
            guard mode == S_IFDIR || mode == S_IFREG else { result.otherItemsSkipped += 1; continue }
            let url = directory.url.appendingPathComponent(name, isDirectory: mode == S_IFDIR)
            if cloudExcluded(url, flags: info.st_flags, relative: relative) { continue }
            if mode == S_IFDIR {
                result.folderCount += 1
                if directory.depth >= options.maximumDepth { limit("Subfolders below depth \(options.maximumDepth) were skipped."); continue }
                let childFD = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                if childFD < 0 { issue(relative, String(cString: strerror(errno))); continue }
                // O_NOFOLLOW and device/inode comparison prevent following a swapped directory/symlink.
                var actual = stat()
                guard fstat(childFD, &actual) == 0, actual.st_dev == info.st_dev, actual.st_ino == info.st_ino else {
                    close(childFD); issue(relative, "Directory changed during enumeration; skipped."); continue
                }
                guard let childStream = fdopendir(childFD) else { let code = errno; close(childFD); issue(relative, String(cString: strerror(code))); continue }
                stack.append(ScanDirectory(stream: childStream, url: url, relative: relative, depth: directory.depth + 1))
                continue
            }
            guard faccessat(fd, name, R_OK, AT_EACCESS) == 0 else { issue(relative, String(cString: strerror(errno))); continue }
            if info.st_nlink > 1 {
                let identity = FileIdentity(device: info.st_dev, inode: info.st_ino)
                if !hardLinks.insert(identity).inserted { result.hardLinksSkipped += 1; continue }
            }
            let logical = max(0, Int64(info.st_size))
            let allocatedResult = max(0, Int64(info.st_blocks)).multipliedReportingOverflow(by: 512)
            let allocated = allocatedResult.overflow ? Int64.max : allocatedResult.partialValue
            byteOverflow = byteOverflow || allocatedResult.overflow
            directory.files += 1
            add(logical, to: &directory.logical); add(allocated, to: &directory.allocated)
            result.fileCount += 1
            add(logical, to: &result.logicalBytes)
            add(allocated, to: &result.allocatedBytes)
            var type = url.pathExtension.lowercased()
            type = type.isEmpty ? "No extension" : (type.count > 64 ? "Other extensions" : "." + type)
            if buckets[type] == nil && buckets.count >= options.maximumTypes { type = "Other extensions" }
            var bucket = buckets[type] ?? AnalyzedType(name: type)
            bucket.count += 1
            add(logical, to: &bucket.logicalBytes); add(allocated, to: &bucket.allocatedBytes)
            buckets[type] = bucket
            let file = AnalyzedFile(url: url, relativePath: relative, logicalBytes: logical, allocatedBytes: allocated)
            insert(file, into: &result.largestLogical, metric: .logical)
            insert(file, into: &result.largestAllocated, metric: .allocated)
        }
        // Releasing the stack closes every directory descriptor, including on stop/error/limits.
        while !stack.isEmpty { closeDirectory(partial: true) }
        if byteOverflow { limit("Byte total exceeded the supported integer range.") }
        if cancellation.isCancelled || Task<Never, Never>.isCancelled { result.state = .stopped }
        else { result.state = forceLimited ? .limited : .complete }
        let final = snapshot()
        progress(final)
        return final
    }
}
