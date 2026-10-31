import SwiftUI
import AppKit
import QuickLookThumbnailing
import PDFKit
import UniformTypeIdentifiers
import ImageIO

func isMarkdown(_ url: URL) -> Bool { ["md", "markdown", "mdown", "mkd", "mkdn"].contains(url.pathExtension.lowercased()) }

@MainActor final class ThumbnailStore {
    static let shared = ThumbnailStore()
    let cache = NSCache<NSString, NSImage>()
    init() { cache.countLimit = 300; cache.totalCostLimit = 32 * 1024 * 1024 }
}

struct FileThumbnail: View {
    let entry: FolderEntry
    var side: CGFloat = 64
    @State private var thumbnail: NSImage?
    var body: some View {
        Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: entry.url.path))
            .resizable().scaledToFit().frame(width: side, height: side)
            .task(id: "\(entry.url.path)|\(entry.size)|\(entry.modified?.timeIntervalSince1970 ?? 0)") {
                thumbnail = nil
                let cacheKey = "\(entry.url.path)|\(entry.size)|\(entry.modified?.timeIntervalSince1970 ?? 0)" as NSString
                guard !entry.isFolder && !entry.isLink else { return }
                if let cached = ThumbnailStore.shared.cache.object(forKey: cacheKey) { thumbnail = cached; return }
                guard (try? LocalFilePolicy.requireLocal(entry.url)) != nil else { return }
                if let type = try? entry.url.resourceValues(forKeys: [.contentTypeKey]).contentType, type.conforms(to: .image), entry.size < 50_000_000,
                   let cgImage = await Task.detached(priority: .utility, operation: { imageThumbnail(entry.url, pixels: 320) }).value {
                    guard !Task.isCancelled else { return }
                    let image = NSImage(cgImage: cgImage, size: .zero)
                    ThumbnailStore.shared.cache.setObject(image, forKey: cacheKey, cost: Int(image.size.width * image.size.height * 4))
                    thumbnail = image
                    return
                }
                let request = QLThumbnailGenerator.Request(fileAt: entry.url, size: NSSize(width: 160, height: 160), scale: 2, representationTypes: .all)
                do {
                    let representation = try await withTaskCancellationHandler(operation: { try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) }, onCancel: { QLThumbnailGenerator.shared.cancel(request) })
                    guard !Task.isCancelled else { return }
                    let image = representation.nsImage
                    ThumbnailStore.shared.cache.setObject(image, forKey: cacheKey, cost: Int(image.size.width * image.size.height * 4))
                    thumbnail = image
                } catch { /* The file's system icon remains visible. */ }
            }
    }
}

func fileSize(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

struct FolderBrowser: View {
    @ObservedObject var model: FolderModel
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: { Image(systemName: "chevron.left") }.disabled(model.current == model.root && model.selected == nil).help("Back (⌘[)").keyboardShortcut("[", modifiers: .command)
                Image(systemName: "folder.fill").font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.current.lastPathComponent).font(.headline).lineLimit(1)
                    Text("PeekKit").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.selected == nil {
                    Picker("Sort", selection: $model.sort) { ForEach(["Name", "Size", "Modified", "Type"], id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 110).help("Sort folders first, then by selected field")
                    Picker("View", selection: $model.mode) {
                        Image(systemName: "square.grid.2x2").accessibilityLabel("Grid").tag("Grid")
                        Image(systemName: "list.bullet").tag("List")
                        Image(systemName: "list.bullet.indent").accessibilityLabel("Tree").tag("Tree")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 110).help("Grid, list or expandable tree")
                }
            }.padding(16)
            Divider()
            if let entry = model.selected {
                FileDetail(entry: entry).id(entry.url)
            } else {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter this folder", text: $model.query).textFieldStyle(.plain).focused($searchFocused)
                    if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(9).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal,16).padding(.vertical,10)
                FolderAnalysisView(analysis: model.analysis, previewFile: model.previewAnalyzedFile)
                if model.loading { Spacer(); ProgressView("Reading folder…"); Spacer() }
                else if let error = model.error {
                    ContentUnavailableView { Label("Unable to read folder", systemImage: "folder.badge.questionmark") } description: { Text(error) } actions: { Button("Try Again") { model.load() } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.mode == "Tree" ? model.treeRows.isEmpty : model.visible.isEmpty {
                    ContentUnavailableView(model.query.isEmpty ? "This folder is empty" : "No matching files", systemImage: model.query.isEmpty ? "folder" : "magnifyingglass", description: Text(model.query.isEmpty ? "Files and subfolders will appear here." : "Try another name."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.mode == "Tree" { tree } else if model.mode == "List" { list } else { grid }
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
                Text(model.mode == "Tree" ? "\(model.treeRows.count) \(model.treeRows.count == 1 ? "tree row" : "tree rows")" : model.query.isEmpty ? "\(model.entries.count) \(model.entries.count == 1 ? "item" : "items")" : "\(model.visible.count) of \(model.entries.count) items").foregroundStyle(.secondary).fixedSize()
                Menu {
                    Toggle("Show hidden files", isOn: $model.showHidden).keyboardShortcut(".", modifiers: [.command, .shift])
                    Button("Refresh") { model.load() }.keyboardShortcut("r", modifiers: .command)
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
        .background(Button("Find") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden())
        .task { model.load() }
        .onChange(of: model.showHidden) { model.load() }
        .onDisappear { model.dispose() }
    }
    var grid: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 12)], spacing: 16) {
                ForEach(model.visible) { entry in
                    Button { model.enter(entry) } label: {
                        VStack(spacing: 8) {
                            FileThumbnail(entry: entry, side: 64).frame(height: 72)
                            Text(entry.name).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.center).frame(height: 32, alignment: .top)
                            Text(entry.isFolder ? "Folder" : fileSize(entry.size)).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(10).background(model.focused == entry.url ? Color.accentColor.opacity(0.16) : Color.clear).contentShape(RoundedRectangle(cornerRadius: 9))
                    }.contextMenu { EntryActions(url: entry.url) }.buttonStyle(FolderCellStyle()).help(entry.isFolder ? "Browse \(entry.name)" : "Preview \(entry.name)")
                }
            }.padding(16)
        }.focusable().onMoveCommand { model.moveFocus($0) }.onKeyPress(.return) { model.openFocused(); return .handled }
        .onChange(of: model.focused) { _, url in if let url { proxy.scrollTo(url, anchor: .center) } }
        }
    }
    var list: some View {
        ScrollViewReader { proxy in
        VStack(spacing: 0) {
            HStack { Text("Name").frame(maxWidth: .infinity, alignment: .leading); Text("Type").frame(width: 100, alignment: .leading); Text("Modified").frame(width: 140, alignment: .leading); Text("Size").frame(width: 85, alignment: .trailing) }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,20).padding(.bottom,6)
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, entry in
                        Button { model.enter(entry) } label: {
                            HStack(spacing: 10) {
                                FileThumbnail(entry: entry, side: 24)
                                Text(entry.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(entry.kind).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(width: 100, alignment: .leading)
                                Text(entry.modified?.formatted(date: .abbreviated, time: .shortened) ?? "—").font(.caption).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
                                Text(entry.isFolder ? "—" : fileSize(entry.size)).font(.caption).foregroundStyle(.secondary).frame(width: 85, alignment: .trailing)
                                Image(systemName: entry.isFolder ? "chevron.right" : "eye").font(.caption2).foregroundStyle(.tertiary).frame(width: 12)
                            }.padding(.horizontal,12).padding(.vertical,6).background(model.focused == entry.url ? Color.accentColor.opacity(0.16) : Color.clear).background(index.isMultiple(of: 2) ? Color.primary.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
                        }.contextMenu { EntryActions(url: entry.url) }.buttonStyle(FolderCellStyle())
                    }
                }.padding(.horizontal,8)
            }
        }.focusable().onMoveCommand { model.moveFocus($0) }.onKeyPress(.return) { model.openFocused(); return .handled }
        .onChange(of: model.focused) { _, url in if let url { proxy.scrollTo(url, anchor: .center) } }
        }
    }
    var tree: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(model.treeRows) { row in
                    HStack(spacing: 8) {
                        if row.entry.isFolder {
                            Button { model.toggle(row.entry) } label: { Image(systemName: model.expanded.contains(row.id) ? "chevron.down" : "chevron.right").frame(width: 16) }
                                .buttonStyle(.plain).accessibilityLabel("Expand or collapse " + row.entry.name)
                        } else { Color.clear.frame(width: 16, height: 1) }
                        Button { model.enter(row.entry) } label: {
                            HStack { FileThumbnail(entry: row.entry, side: 22); Text(row.entry.name).lineLimit(1); Spacer(); Text(row.entry.kind).foregroundStyle(.secondary).lineLimit(1).frame(width: 110); Text(row.entry.isFolder ? "—" : fileSize(row.entry.size)).monospacedDigit().frame(width: 85, alignment: .trailing) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).contextMenu { EntryActions(url: row.id) }
                    }.padding(.leading, CGFloat(row.depth * 18)).padding(7)
                     .background(model.focused == row.id ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    if let message = model.treeMessages[row.id] { Text(message).font(.caption).foregroundStyle(.secondary).padding(.leading, CGFloat(row.depth * 18 + 25)) }
                }
                Text("Tree expands on demand · filters loaded names · up to 2,000 children per folder / 10,000 cached entries").font(.caption2).foregroundStyle(.secondary).padding(8)
            }.padding(8)
        }.focusable().onMoveCommand { model.moveFocus($0) }.onKeyPress(.return) { model.openFocused(); return .handled }
        .onChange(of: model.focused) { _, url in if let url { proxy.scrollTo(url, anchor: .center) } }
        }
    }
}
struct FolderCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.background(configuration.isPressed ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(.primary) }
}

struct FileDetail: View {
    let entry: FolderEntry
    @State private var showingInspector = false
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
                Button { showingInspector = true } label: { Image(systemName: "info.circle") }
                    .help("File information").accessibilityLabel("File information")
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
        }.sheet(isPresented: $showingInspector) { FileInspectorView(url: entry.url) }
        .task(id: entry.url) {
            markdown = false; text = nil; image = nil; pdf = nil; ready = false
            defer { ready = true }
            let url = entry.url
            let worker = Task.detached(priority: .userInitiated) { try PreviewPayload.load(url) }
            do {
                let payload = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled else { return }
                switch payload {
                case .markdown: markdown = true
                case .image(let cg): image = NSImage(cgImage: cg, size: .zero)
                case .pdf(let document): pdf = document
                case .text(let value): text = value
                case .unsupported: break
                }
            } catch { if !Task.isCancelled { text = error.localizedDescription } }
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
