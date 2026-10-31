import Foundation

extension FolderAnalysisSnapshot {
    func jsonSummary() throws -> String {
        func item(_ file: AnalyzedFile) -> [String: Any] { ["path": file.relativePath, "logicalBytes": file.logicalBytes, "allocatedBytes": file.allocatedBytes, "partial": file.partial, "measuredFiles": file.fileCount] }
        let value: [String: Any] = [
            "schemaVersion": 1, "root": root.path, "state": state.rawValue, "partial": isPartial, "elapsedSeconds": elapsedSeconds,
            "scope": ["recursive": true, "hiddenIncluded": includeHidden, "packagesIncluded": true, "symlinksFollowed": false, "crossVolumes": false, "directoryMetadataIncluded": false, "hardLinks": "counted once; assigned to first visited directory", "allocatedMeaning": "allocated file blocks; not reclaimable or exclusive space"],
            "totals": ["logicalBytes": logicalBytes, "allocatedBytes": allocatedBytes, "files": fileCount, "folders": folderCount, "checked": visitedEntries],
            "omissions": ["hidden": hiddenEntriesSkipped, "symbolicLinks": symbolicLinksSkipped, "duplicateHardLinks": hardLinksSkipped, "cloud": cloudItemsSkipped, "unknownResidency": unknownCloudMetadata, "unreadable": unreadableItems, "otherVolumes": otherVolumesSkipped, "special": otherItemsSkipped],
            "types": sortedTypes(.logical).map { ["extension": $0.name, "count": $0.count, "logicalBytes": $0.logicalBytes, "allocatedBytes": $0.allocatedBytes] as [String: Any] },
            "largestFilesBySize": largestLogical.map(item), "largestFilesByAllocation": largestAllocated.map(item),
            "largestFoldersBySize": largestLogicalFolders.map(item), "largestFoldersByAllocation": largestAllocatedFolders.map(item),
            "issues": issues.map { ["path": $0.path, "reason": $0.message] }, "limits": limitReasons
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
    func csvSummary() -> String {
        func field(_ value: String) -> String {
            let risky = value.trimmingCharacters(in: .whitespacesAndNewlines).first.map { "=+-@".contains($0) } ?? false
            let safe = risky || value.first == "\t" || value.first == "\r" ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = [["section", "name_or_path", "count", "logical_bytes", "allocated_bytes", "partial_or_note"], ["scope", root.path, "", "", "", "\(state.rawValue); recursive; hidden=\(includeHidden); packages included; file blocks are not reclaimable space"], ["total", "Measured readable files", String(fileCount), String(logicalBytes), String(allocatedBytes), String(isPartial)]]
        rows += sortedTypes(.logical).map { ["type", $0.name, String($0.count), String($0.logicalBytes), String($0.allocatedBytes), String(isPartial)] }
        for (section, values) in [("file_size", largestLogical), ("file_allocation", largestAllocated), ("folder_size_overlapping", largestLogicalFolders), ("folder_allocation_overlapping", largestAllocatedFolders)] {
            rows += values.map { [section, $0.relativePath, String($0.fileCount), String($0.logicalBytes), String($0.allocatedBytes), String($0.partial || isPartial)] }
        }
        rows += issues.map { ["issue", $0.path, "", "", "", $0.message] }
        rows += [["omissions", "hidden/symlinks/hardlinks/cloud/unknown/unreadable/volumes/special", "", "", "", "\(hiddenEntriesSkipped)/\(symbolicLinksSkipped)/\(hardLinksSkipped)/\(cloudItemsSkipped)/\(unknownCloudMetadata)/\(unreadableItems)/\(otherVolumesSkipped)/\(otherItemsSkipped)"]]
        rows += limitReasons.map { ["limit", $0, "", "", "", "partial"] }
        return rows.map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
