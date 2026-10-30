import SwiftUI
import AppKit

struct FolderAnalysisView: View {
    @ObservedObject var analysis: FolderAnalysisModel
    let previewFile: (URL) -> Void
    @State private var expanded = false
    @State private var tab = "File types"
    @State private var metric: AnalysisMetric = .allocated

    var body: some View {
        if let snapshot = analysis.snapshot {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Button { expanded.toggle() } label: {
                        Label(expanded ? "Hide analysis" : "Analysis", systemImage: "chart.bar.xaxis")
                    }.buttonStyle(.borderless).help("Recursive folder size, file types, largest files and scope")
                    Text("Recursive: \(fileSize(snapshot.logicalBytes)) size · \(fileSize(snapshot.allocatedBytes)) on disk")
                        .lineLimit(1).minimumScaleFactor(0.8).monospacedDigit()
                    Spacer(minLength: 4)
                    if snapshot.state == .scanning {
                        ProgressView().controlSize(.small)
                        Text("\(snapshot.visitedEntries.formatted()) checked").foregroundStyle(.secondary).monospacedDigit()
                        Button(analysis.stopping ? "Stopping…" : "Stop") { analysis.stop() }.disabled(analysis.stopping)
                    } else {
                        Text(status(snapshot)).foregroundStyle(snapshot.isPartial ? .orange : .secondary)
                        Button { analysis.restart() } label: { Image(systemName: "arrow.clockwise") }.help("Rescan folder")
                    }
                }.font(.caption).padding(.horizontal, 16).padding(.vertical, 10)
                if expanded {
                    VStack(spacing: 9) {
                        HStack {
                            Picker("Analysis section", selection: $tab) {
                                Text("File types").tag("File types")
                                Text("Largest files").tag("Largest files")
                                Text("Scope & omissions").tag("Scope")
                            }.pickerStyle(.segmented).labelsHidden()
                            if tab != "Scope" {
                                Picker("Size metric", selection: $metric) {
                                    ForEach(AnalysisMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }.labelsHidden().frame(width: 100)
                            }
                        }
                        ScrollView {
                            if tab == "File types" { types(snapshot) }
                            else if tab == "Largest files" { largest(snapshot) }
                            else { scope(snapshot) }
                        }.frame(height: 166)
                        Text("Current folder + descendants · \(snapshot.includeHidden ? "hidden included" : "hidden excluded") · packages included · name filter does not affect analysis")
                            .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.horizontal, 16).padding(.bottom, 12)
                }
                Divider()
            }.background(Color.primary.opacity(0.025))
        }
    }
    private func status(_ s: FolderAnalysisSnapshot) -> String {
        switch s.state {
        case .scanning: return "Scanning"
        case .stopped: return "Stopped · partial"
        case .limited: return "Limit reached · partial"
        case .complete: return s.isPartial ? "Partial · \(s.fileCount.formatted()) files" : "\(s.fileCount.formatted()) files"
        }
    }
    private func types(_ s: FolderAnalysisSnapshot) -> some View {
        LazyVStack(spacing: 8) {
            if s.types.isEmpty { Text(s.state == .scanning ? "Reading file metadata…" : "No local readable files in this scope.").foregroundStyle(.secondary).padding(18) }
            ForEach(s.sortedTypes(metric)) { type in
                HStack(spacing: 12) {
                    Text(type.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(type.count.formatted()) files").foregroundStyle(.secondary).monospacedDigit().frame(width: 88, alignment: .trailing)
                    ProgressView(value: Double(type.bytes(metric)), total: Double(max(1, metric == .logical ? s.logicalBytes : s.allocatedBytes))).frame(width: 60)
                    Text(fileSize(type.bytes(metric))).monospacedDigit().frame(width: 95, alignment: .trailing)
                }.font(.caption)
            }
        }.padding(.vertical, 6)
    }
    private func largest(_ s: FolderAnalysisSnapshot) -> some View {
        LazyVStack(spacing: 7) {
            if s.largest(metric).isEmpty { Text("No local readable files in this scope.").foregroundStyle(.secondary).padding(18) }
            ForEach(s.largest(metric)) { file in
                Button { previewFile(file.url) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.url.lastPathComponent).lineLimit(1)
                            Text(file.relativePath).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(fileSize(file.bytes(metric))).monospacedDigit()
                        Image(systemName: "eye").foregroundStyle(.secondary)
                    }.padding(.vertical, 3).contentShape(Rectangle())
                }.buttonStyle(.plain).font(.caption).help(file.relativePath)
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                    Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.url.path, forType: .string) }
                }
            }
        }
    }
    private func scope(_ s: FolderAnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(s.root.path).textSelection(.enabled).font(.caption).lineLimit(2)
            Text("\(s.fileCount.formatted()) measured files · \(s.folderCount.formatted()) subfolders found · \(s.visitedEntries.formatted()) entries checked · \(s.elapsedSeconds, specifier: "%.1f") s")
            Text("Size is logical file length. On disk is allocated file blocks, not exclusive or reclaimable space on APFS. Hard links are counted once; directory metadata is excluded.")
            Text("\(s.includeHidden ? "Includes" : "Excludes") hidden entries. Application/package contents are included. Symbolic links and other volumes are not followed. Cloud-only or uncertain-residency entries are skipped without reading/downloading content.")
            Text("Skipped: \(s.hiddenEntriesSkipped) hidden entries/subtrees · \(s.symbolicLinksSkipped) symbolic links · \(s.hardLinksSkipped) duplicate hard links · \(s.cloudItemsSkipped) cloud entries/subtrees · \(s.unknownCloudMetadata) unknown cloud metadata · \(s.otherVolumesSkipped) other volumes · \(s.otherItemsSkipped) special items.")
            Text("Unreadable or changed entries: \(s.unreadableItems). Descendant counts and sizes inside skipped subtrees are unknown. A scan is a live observation, not a filesystem snapshot.")
            ForEach(s.limitReasons, id: \.self) { Text($0).foregroundStyle(.orange) }
            if !s.issues.isEmpty {
                Text("First \(s.issues.count) issues:").fontWeight(.semibold)
                ForEach(s.issues) { issue in Text("\(issue.path): \(issue.message)").textSelection(.enabled) }
            }
            Text("Limits: 1,000,000 entries, 128 directory levels, 60 seconds, 20 largest files per metric, 256 extension buckets plus Other extensions. Results remain partial when stopped or limited.").foregroundStyle(.secondary)
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }
}
