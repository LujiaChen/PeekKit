import SwiftUI
import AppKit
import QuickLookThumbnailing
import PDFKit
import UniformTypeIdentifiers
import ImageIO

func isMarkdown(_ url: URL) -> Bool { ["md", "markdown", "mdown", "mkd", "mkdn"].contains(url.pathExtension.lowercased()) }

struct FolderEntry: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    let isFolder: Bool
    let isLink: Bool
    let size: Int64
    let modified: Date?
    let kind: String
    static func read(_ folder: URL, showHidden: Bool) throws -> ([FolderEntry], Bool) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey]
        var enumerationError: Error?
        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]
        if !showHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: options, errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw CocoaError(.fileReadNoPermission) }
        var entries: [FolderEntry] = []
        var truncated = false
        while let url = enumerator.nextObject() as? URL {
            try Task<Never, Never>.checkCancellation()
            if entries.count == 20_000 { truncated = true; break }
            let v = try? url.resourceValues(forKeys: keys)
            entries.append(FolderEntry(url: url, name: url.lastPathComponent, isFolder: v?.isDirectory == true && v?.isPackage != true && v?.isSymbolicLink != true, isLink: v?.isSymbolicLink == true, size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate, kind: v?.localizedTypeDescription ?? "File"))
        }
        if let enumerationError { throw enumerationError }
        return (entries, truncated)
    }
}

@MainActor final class FolderModel: ObservableObject {
    @Published var root: URL
    @Published var current: URL
    @Published var entries: [FolderEntry] = []
    @Published var selected: FolderEntry?
    @Published var query = ""
    @Published var loading = false
    @Published var error: String?
    @Published var truncated = false
    @Published var showHidden = false
    @Published var listMode = UserDefaults.standard.bool(forKey: "listMode")
    @Published var sort = "Name"
    let analysis = FolderAnalysisModel()
    private var listingTask: Task<Void, Never>?
    private var listingWorker: Task<([FolderEntry], Bool), Error>?
    private var generation = 0
    init(root: URL) { self.root = root; self.current = root }
    var visible: [FolderEntry] {
        entries.filter { query.isEmpty || $0.name.localizedStandardContains(query) }.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            switch sort {
            case "Size": if a.size != b.size { return a.size > b.size }
            case "Modified": if a.modified != b.modified { return (a.modified ?? .distantPast) > (b.modified ?? .distantPast) }
            default: break
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    var crumbs: [URL] {
        var result = [current]; var p = current
        while p != root && p.pathComponents.count > root.pathComponents.count {
            p.deleteLastPathComponent(); result.insert(p, at: 0)
        }
        return result
    }
    func load(_ url: URL? = nil) {
        if let url { current = url; selected = nil; query = "" }
        generation += 1; let token = generation
        loading = true; error = nil
        let folder = current; let hidden = showHidden
        listingTask?.cancel()
        listingWorker?.cancel()
        analysis.start(root: folder, includeHidden: hidden)
        let worker = Task.detached(priority: .userInitiated) { try FolderEntry.read(folder, showHidden: hidden) }
        listingWorker = worker
        listingTask = Task { [weak self] in
            do {
                let result = try await worker.value
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.entries = result.0
                self.truncated = result.1
                self.loading = false
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.entries = []
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }
    func dispose() {
        generation += 1
        listingTask?.cancel()
        listingWorker?.cancel()
        analysis.cancel()
    }
    func previewAnalyzedFile(_ url: URL) {
        guard url.path.hasPrefix(current.path == "/" ? "/" : current.path + "/"),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .localizedTypeDescriptionKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return }
        selected = FolderEntry(url: url, name: url.lastPathComponent, isFolder: false, isLink: false, size: Int64(values.fileSize ?? 0), modified: nil, kind: values.localizedTypeDescription ?? "File")
    }
    deinit { listingTask?.cancel(); listingWorker?.cancel() }
    func enter(_ entry: FolderEntry) { if entry.isFolder { load(entry.url) } else { selected = entry } }
    func back() { if selected != nil { selected = nil } else if current != root { load(current.deletingLastPathComponent()) } }
}

@MainActor final class ThumbnailStore {
    static let shared = ThumbnailStore()
    let cache = NSCache<NSURL, NSImage>()
    init() { cache.countLimit = 300 }
}

struct FileThumbnail: View {
    let entry: FolderEntry
    var side: CGFloat = 64
    @State private var thumbnail: NSImage?
    var body: some View {
        Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: entry.url.path))
            .resizable().scaledToFit().frame(width: side, height: side)
            .task(id: entry.url) {
                thumbnail = nil
                guard !entry.isFolder && !entry.isLink else { return }
                if let cached = ThumbnailStore.shared.cache.object(forKey: entry.url as NSURL) { thumbnail = cached; return }
                let values = try? entry.url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                if values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current { return }
                if let type = try? entry.url.resourceValues(forKeys: [.contentTypeKey]).contentType, type.conforms(to: .image), entry.size < 50_000_000,
                   let cgImage = await Task.detached(priority: .utility, operation: { imageThumbnail(entry.url, pixels: 320) }).value {
                    let image = NSImage(cgImage: cgImage, size: .zero)
                    ThumbnailStore.shared.cache.setObject(image, forKey: entry.url as NSURL)
                    thumbnail = image
                    return
                }
                let request = QLThumbnailGenerator.Request(fileAt: entry.url, size: NSSize(width: 160, height: 160), scale: 2, representationTypes: .all)
                do {
                    let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                    guard !Task.isCancelled else { return }
                    let image = representation.nsImage
                    ThumbnailStore.shared.cache.setObject(image, forKey: entry.url as NSURL)
                    thumbnail = image
                } catch { /* The file's system icon remains visible. */ }
            }
    }
}

func fileSize(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

struct FolderBrowser: View {
    @ObservedObject var model: FolderModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: { Image(systemName: "chevron.left") }.disabled(model.current == model.root && model.selected == nil).help("Back")
                Image(systemName: "folder.fill").font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.current.lastPathComponent).font(.headline).lineLimit(1)
                    Text("PeekKit").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.selected == nil {
                    Picker("Sort", selection: $model.sort) { Text("Name").tag("Name"); Text("Size").tag("Size"); Text("Modified").tag("Modified") }.labelsHidden().frame(width: 110).help("Sort folders first, then by selected field")
                    Picker("View", selection: $model.listMode) {
                        Image(systemName: "square.grid.2x2").tag(false)
                        Image(systemName: "list.bullet").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 76).help("Grid or list view")
                    .onChange(of: model.listMode) { _, v in UserDefaults.standard.set(v, forKey: "listMode") }
                }
            }.padding(16)
            Divider()
            if let entry = model.selected {
                FileDetail(entry: entry).id(entry.url)
            } else {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter this folder", text: $model.query).textFieldStyle(.plain)
                    if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(9).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal,16).padding(.vertical,10)
                FolderAnalysisView(analysis: model.analysis, previewFile: model.previewAnalyzedFile)
                if model.loading { Spacer(); ProgressView("Reading folder…"); Spacer() }
                else if let error = model.error {
                    ContentUnavailableView { Label("Unable to read folder", systemImage: "folder.badge.questionmark") } description: { Text(error) } actions: { Button("Try Again") { model.load() } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.visible.isEmpty {
                    ContentUnavailableView(model.query.isEmpty ? "This folder is empty" : "No matching files", systemImage: model.query.isEmpty ? "folder" : "magnifyingglass", description: Text(model.query.isEmpty ? "Files and subfolders will appear here." : "Try another name."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.listMode { list } else { grid }
            }
            Divider()
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(model.crumbs, id: \.self) { url in
                            if url != model.root { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                            Button(url.lastPathComponent) { model.load(url) }.buttonStyle(.plain).lineLimit(1).foregroundStyle(url == model.current ? .primary : .secondary)
                        }
                    }
                }
                Spacer(minLength: 12)
                Text(model.query.isEmpty ? "\(model.entries.count) \(model.entries.count == 1 ? "item" : "items")" : "\(model.visible.count) of \(model.entries.count) items").foregroundStyle(.secondary).fixedSize()
                Menu {
                    Toggle("Show hidden files", isOn: $model.showHidden)
                    Button("Refresh") { model.load() }
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 15)) }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .frame(width: 28, height: 24)
                    .padding(.leading, 6)
                    .accessibilityLabel("Folder options")
                    .help("Folder options")
            }.font(.caption).padding(12)
            if model.truncated { Text("Showing the first 20,000 items. Open a subfolder to narrow the view.").font(.caption).foregroundStyle(.secondary).padding(.bottom,8) }
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { model.load() }
        .onChange(of: model.showHidden) { model.load() }
        .onDisappear { model.dispose() }
    }
    var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 12)], spacing: 16) {
                ForEach(model.visible) { entry in
                    Button { model.enter(entry) } label: {
                        VStack(spacing: 8) {
                            FileThumbnail(entry: entry, side: 64).frame(height: 72)
                            Text(entry.name).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.center).frame(height: 32, alignment: .top)
                            Text(entry.isFolder ? "Folder" : fileSize(entry.size)).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(10).contentShape(RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(FolderCellStyle()).help(entry.isFolder ? "Browse \(entry.name)" : "Preview \(entry.name)")
                }
            }.padding(16)
        }
    }
    var list: some View {
        VStack(spacing: 0) {
            HStack { Text("Name").frame(maxWidth: .infinity, alignment: .leading); Text("Modified").frame(width: 140, alignment: .leading); Text("Size").frame(width: 85, alignment: .trailing) }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,20).padding(.bottom,6)
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, entry in
                        Button { model.enter(entry) } label: {
                            HStack(spacing: 10) {
                                FileThumbnail(entry: entry, side: 24)
                                Text(entry.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(entry.modified?.formatted(date: .abbreviated, time: .shortened) ?? "—").font(.caption).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
                                Text(entry.isFolder ? "—" : fileSize(entry.size)).font(.caption).foregroundStyle(.secondary).frame(width: 85, alignment: .trailing)
                                Image(systemName: entry.isFolder ? "chevron.right" : "eye").font(.caption2).foregroundStyle(.tertiary).frame(width: 12)
                            }.padding(.horizontal,12).padding(.vertical,6).background(index.isMultiple(of: 2) ? Color.primary.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
                        }.buttonStyle(FolderCellStyle())
                    }
                }.padding(.horizontal,8)
            }
        }
    }
}
struct FolderCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.background(configuration.isPressed ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(.primary) }
}

struct FileDetail: View {
    let entry: FolderEntry
    @State private var markdown = false
    @State private var text: String?
    @State private var image: NSImage?
    @State private var pdf: PDFDocument?
    @State private var ready = false
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                FileThumbnail(entry: entry, side: 32)
                VStack(alignment: .leading) { Text(entry.name).font(.headline).textSelection(.enabled); Text("\(entry.kind) · \(fileSize(entry.size))").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }.padding(.horizontal,20).padding(.top,16)
            if markdown {
                #if FOLDER_EXTENSION
                NativeMarkdownContent(url: entry.url).id(entry.url)
                #else
                MarkdownContent(url: entry.url).id(entry.url)
                #endif
            }
            else if let image { GeometryReader { geo in Image(nsImage: image).resizable().scaledToFit().frame(width: geo.size.width,height: geo.size.height) }.padding(16) }
            else if let pdf { PDFContent(document: pdf) }
            else if let text { ScrollView([.vertical,.horizontal]) { Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity,alignment: .topLeading).padding(20) } }
            else if !ready { Spacer(); ProgressView(); Spacer() }
            else { Spacer(); FileThumbnail(entry: entry, side: 100); Text("\(entry.kind)").foregroundStyle(.secondary); Text("Use Finder to open this file in its app.").font(.caption).foregroundStyle(.secondary); Spacer() }
        }.task(id: entry.url) {
            markdown = false; text = nil; image = nil; pdf = nil; ready = false
            defer { ready = true }
            guard !entry.isLink else { return }
            let values = try? entry.url.resourceValues(forKeys: [.contentTypeKey,.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey])
            if values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current { return }
            if isMarkdown(entry.url) { markdown = true }
            else if values?.contentType?.conforms(to: .image) == true, entry.size < 50_000_000 {
                if let cg = await Task.detached(priority: .userInitiated, operation: { imageThumbnail(entry.url, pixels: 1800) }).value { image = NSImage(cgImage: cg, size: .zero) }
            } else if values?.contentType?.conforms(to: .pdf) == true, entry.size < 50_000_000 { pdf = PDFDocument(url: entry.url) }
            else if entry.size < 10_000_000, values?.contentType?.conforms(to: .text) == true || ["md","json","yaml","yml","swift","py","js","ts","csv","log","sh"].contains(entry.url.pathExtension.lowercased()) {
                if let handle = try? FileHandle(forReadingFrom: entry.url) {
                    let data = try? handle.read(upToCount: 128_000); try? handle.close()
                    if let data, let decoded = String(data: data,encoding: .utf8) { text = decoded + (entry.size > 128_000 ? "\n\n… Preview limited to the first 128 KB." : "") }
                }
            }
        }
    }
}
struct PDFContent: NSViewRepresentable {
    let document: PDFDocument
    func makeNSView(context: Context) -> PDFView { let v = PDFView(); v.autoScales = true; v.document = document; return v }
    func updateNSView(_ view: PDFView, context: Context) { view.document = document }
}

func imageThumbnail(_ url: URL, pixels: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary)
}
