import SwiftUI
import ImageIO
import PDFKit
import os

struct ArchiveBrowser: View {
    let url: URL
    @State private var cancelled = false
    @FocusState private var browserFocused: Bool
    @State private var listing: ArchiveListing?
    @State private var error: String?
    @State private var current = ""
    @State private var query = ""
    @State private var sort = "Name"
    @AppStorage("archiveTree") private var tree = true
    @State private var expanded: Set<String> = []
    @State private var rows: [ArchiveItem] = []
    @State private var selected: ArchiveItem?
    @State private var focused: String?
    private var presentationID: String { [url.absoluteString,current,query,sort,String(tree),expanded.sorted().joined(separator:"|"),String(listing?.items.count ?? -1)].joined(separator:"|") }
    var body: some View {
        VStack(spacing:12) {
            toolbar
            if let selected { ArchiveEntryPreview(url:url,entry:selected).id(selected.path) }
            else if let listing {
                HStack { Image(systemName:"magnifyingglass"); TextField("Search archive paths",text:$query).textFieldStyle(.roundedBorder) }
                Text("\(listing.format) · \(fileSize(Int64(listing.compressedBytes))) archive · \(listing.items.count) nodes").font(.caption).foregroundStyle(.secondary)
                contentRows
                HStack { Button("Archive root") { current = "" }; Text(current).lineLimit(1); Spacer(); Text("Uncompressed sizes · no disk extraction").foregroundStyle(.secondary) }.font(.caption)
            } else if let error { ContentUnavailableView("Unable to read archive",systemImage:"archivebox",description:Text(error)); Button("Retry") { cancelled = false } }
            else { ProgressView("Validating archive…"); Button("Cancel") { cancelled = true }; Spacer() }
        }.padding(16).frame(minWidth:600,maxWidth:.infinity,minHeight:400,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor))
        .onChange(of:url) { cancelled = false }
        .task(id:url.absoluteString+String(cancelled)) {
            listing = nil; error = nil; selected = nil; rows = []; current = ""; expanded = []; focused = nil; query = ""
            if cancelled { error = "Archive reading cancelled"; return }
            let worker = Task.detached(priority:.userInitiated) { try ArchiveReader.list(url) }
            do { let value = try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()}); if !Task.isCancelled { Logger(subsystem:"com.lukechen.peekkit",category:"Archive").notice("Archive ready: \(value.items.count) nodes in \(Bundle.main.bundleIdentifier ?? "unknown", privacy:.public)"); listing = value; if CommandLine.arguments.contains("--tree-demo") { tree = true; expanded = Set(value.items.filter(\.directory).map(\.path)) }; if CommandLine.arguments.contains("--directory-demo") { tree = false } } }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .task(id: presentationID) {
            let items = listing?.items ?? []; let root = current; let search = query; let mode = tree; let open = expanded; let ordering = sort
            let worker = Task.detached { items.filter { item in
                if !search.isEmpty { return item.path.localizedStandardContains(search) }
                if !mode { return item.parent == root }
                let parts = item.path.split(separator:"/")
                return (1..<parts.count).allSatisfy { open.contains(parts.prefix($0).joined(separator:"/")) }
            }.sorted { a,b in
                if mode { return a.path.localizedStandardCompare(b.path) == .orderedAscending }
                if a.directory != b.directory { return a.directory }
                if ordering == "Size", a.size != b.size { return a.size > b.size }
                if ordering == "Modified", a.modified != b.modified { return (a.modified ?? .distantPast) > (b.modified ?? .distantPast) }
                if ordering == "Type", (a.path as NSString).pathExtension != (b.path as NSString).pathExtension { return (a.path as NSString).pathExtension < (b.path as NSString).pathExtension }
                return a.path.localizedStandardCompare(b.path) == .orderedAscending
            } }
            let result = await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()}); if !Task.isCancelled { rows = result }
        }
    }
    private var toolbar: some View {
HStack {
                Button { if selected != nil { selected = nil } else { current = (current as NSString).deletingLastPathComponent } } label: { Image(systemName:"chevron.left") }.disabled(selected == nil && current.isEmpty).accessibilityLabel("Back")
                Image(systemName:"archivebox.fill").foregroundStyle(.blue)
                Text(url.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Toggle("Tree",isOn:$tree).toggleStyle(.button)
                Picker("Sort",selection:$sort) { ForEach(["Name","Size","Type","Modified"],id:\.self) { Text($0) } }.frame(width:125).disabled(tree).help("Field sorting is available in directory view")
            }
    }
    private var contentRows: some View {
ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing:2) {
                            ForEach(rows) { item in
                                HStack {
                                    if tree && item.directory { Button { if !expanded.insert(item.path).inserted { expanded.remove(item.path) } } label: { Image(systemName:expanded.contains(item.path) ? "chevron.down" : "chevron.right") }.accessibilityLabel("Expand or collapse " + item.name).buttonStyle(.plain) }
                                    Button { open(item) } label: {
                                        HStack {
                                            Image(systemName:item.directory ? "folder.fill" : "doc").foregroundStyle(.blue)
                                            Text(query.isEmpty ? item.name : item.path).lineLimit(1)
                                            Spacer()
                                            Text(item.directory ? "Folder" : (item.name as NSString).pathExtension.uppercased()).foregroundStyle(.secondary)
                                            Text(item.directory ? "—" : fileSize(item.size)).frame(width:90,alignment:.trailing)
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }.padding(.leading, tree && query.isEmpty ? CGFloat(item.path.split(separator:"/").count-1)*14 : 0).padding(7)
                                 .background(focused == item.path ? Color.accentColor.opacity(0.15) : .clear).id(item.path)
                            }
                            if rows.isEmpty { Text(query.isEmpty ? "This archive directory is empty" : "No matches").foregroundStyle(.secondary).padding() }
                        }
                    }.focusable().focused($browserFocused).onAppear { browserFocused = true }.onMoveCommand { direction in
                        if direction == .left {
                            if tree, let focused { if expanded.contains(focused) { expanded.remove(focused) } else { self.focused = (focused as NSString).deletingLastPathComponent } }
                            else { current = (current as NSString).deletingLastPathComponent }
                            return
                        }
                        let index = rows.firstIndex{$0.path == focused} ?? -1
                        if direction == .right, index >= 0 { let item = rows[index]; if tree && item.directory && !expanded.contains(item.path) { expanded.insert(item.path) } else { open(item) }; return }
                        guard !rows.isEmpty else { return }
                        focused = rows[max(0,min(rows.count-1,index + (direction == .up ? -1 : 1)))].path
                    }.onKeyPress(.return) { if let item = rows.first(where:{$0.path == focused}) { open(item) }; return .handled }
                     .onChange(of:focused) { _,value in if let value { proxy.scrollTo(value) } }
                }
    }
    private func open(_ item: ArchiveItem) {
        focused = item.path
        if item.directory { tree = false; current = item.path; query = "" } else { selected = item }
    }
}
struct ArchiveEntryPreview: View {
    let url: URL
    let entry: ArchiveItem
    @State private var text: String?
    @State private var image: NSImage?
    @State private var pdf: PDFDocument?
    @State private var rendered: NSAttributedString?
    @State private var showSource = false
    var body: some View {
        VStack(alignment:.leading) {
            Text(entry.path).font(.headline).textSelection(.enabled)
            Text("\(fileSize(entry.size)) uncompressed · \(entry.modified?.formatted() ?? "Date unavailable")").font(.caption).textSelection(.enabled)
            if let image { Image(nsImage:image).resizable().scaledToFit() }
            else if let pdf { PDFContent(document:pdf) }
            else if let rendered, !showSource { NativeMarkdownText(content:rendered) }
            else if let text { ScrollView { Text(text).font(.system(.body,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) } }
            else { ProgressView("Reading entry…") }
            if rendered != nil { Toggle("View Markdown source",isOn:$showSource).toggleStyle(.button) }
            Spacer(minLength:0)
        }.task(id:entry.path) {
            let ext = (entry.path as NSString).pathExtension.lowercased()
            let worker = Task.detached(priority:.userInitiated) { () -> (Data, CGImage?, PDFDocument?) in
                let data = try ArchiveReader.preview(url,path:entry.path)
                try Task<Never,Never>.checkCancellation()
                if ["png","jpg","jpeg","gif","webp","tif","tiff"].contains(ext), let source = CGImageSourceCreateWithData(data as CFData,nil) {
                    let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1800] as CFDictionary)
                    return (Data(),image,nil)
                }
                if ext == "pdf" { return (Data(),nil,PDFDocument(data:data)) }
                return (Data(data.prefix(128_000)),nil,nil)
            }
            do {
                let (data,cg,document) = try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                guard !Task.isCancelled else { return }
                if let cg { image = NSImage(cgImage:cg,size:.zero) }
                else if let document { pdf = document }
                else {
                    var value: String?
                    for trim in 0...min(3,data.count) { if let decoded = String(data:data.dropLast(trim),encoding:.utf8) { value = decoded; break } }
                    if let value {
                        text = value + (entry.size > 128_000 ? "\nPreview limited to 128 KB" : "")
                        if ["md","markdown","mdown","mkd","mkdn"].contains(ext), entry.size <= 128_000 { rendered = try nativeMarkdown(value) }
                    } else { text = "No built-in preview for this entry." }
                }
            } catch { if !Task.isCancelled { text = error.localizedDescription } }
        }
    }
}
