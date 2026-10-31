import SwiftUI
import Combine

struct TreeRow: Identifiable { var id: URL { entry.url }; let entry: FolderEntry; let depth: Int }

@MainActor final class FolderModel: ObservableObject {
    @Published var root: URL
    @Published var current: URL
    @Published var entries: [FolderEntry] = [] { didSet { present() } }
    @Published private(set) var visible: [FolderEntry] = []
    @Published var selected: FolderEntry?
    @Published var focused: URL?
    @Published var query = "" { didSet { present() } }
    @Published var loading = false
    @Published var error: String?
    @Published var truncated = false
    @Published var showHidden = false
    @Published var mode: String { didSet { preferences.set(mode, forKey: "browserMode") } }
    @Published var sort: String { didSet { preferences.set(sort, forKey: "browserSort"); present() } }
    @Published private(set) var treeRows: [TreeRow] = []
    @Published private(set) var expanded: Set<URL> = []
    @Published private(set) var treeMessages: [URL: String] = [:]
    let analysis = FolderAnalysisModel()
    private var children: [URL: [FolderEntry]] = [:]
    private var treeTasks: [URL: Task<Void, Never>] = [:]
    private var treeWorkers: [URL: Task<([FolderEntry], Bool), Error>] = [:]
    private var treeRequests: [URL: UUID] = [:]
    private var presentation: Task<Void, Never>?
    private var listingTask: Task<Void, Never>?
    private var listingWorker: Task<([FolderEntry], Bool), Error>?
    private var generation = UUID()
    private var presentationID = UUID()
    private let preferences: UserDefaults
    init(root: URL, preferences: UserDefaults = .standard) {
        self.root = root; self.current = root; self.preferences = preferences
        mode = preferences.string(forKey: "browserMode") ?? (preferences.bool(forKey: "listMode") ? "List" : "Grid")
        sort = preferences.string(forKey: "browserSort") ?? "Name"
    }
    var crumbs: [URL] {
        var result = [current]; var p = current
        while p != root && p.pathComponents.count > root.pathComponents.count { p.deleteLastPathComponent(); result.insert(p, at: 0) }
        return result
    }
    private func present() {
        presentation?.cancel()
        let id = UUID(); presentationID = id
        let input = entries; let sort = sort; let query = query; let hiddenChildren = children; let expanded = expanded
        presentation = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () -> ([FolderEntry], [TreeRow]) in
                let sorted = FolderOrdering.sorted(input, by: sort)
                let visible = sorted.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
                func rows(_ items: [FolderEntry], depth: Int) -> [TreeRow] {
                    guard depth < 64, !Task.isCancelled else { return [] }
                    var result: [TreeRow] = []
                    for entry in items {
                        let nested = expanded.contains(entry.url) ? rows(FolderOrdering.sorted(hiddenChildren[entry.url] ?? [], by: sort), depth: depth + 1) : []
                        if query.isEmpty || entry.name.localizedStandardContains(query) || !nested.isEmpty { result.append(TreeRow(entry: entry, depth: depth)); result += nested }
                    }
                    return result
                }
                return (visible, rows(sorted, depth: 0))
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard let self, self.presentationID == id, !Task.isCancelled else { return }
            self.visible = result.0; self.treeRows = result.1
        }
    }
    func load(_ url: URL? = nil) {
        if let url {
            guard url.standardizedFileURL.path == root.standardizedFileURL.path || url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path == "/" ? "/" : root.standardizedFileURL.path + "/") else { return }
            current = url; selected = nil; query = ""
        }
        dispose()
        let token = generation
        loading = true; error = nil; focused = nil; entries = []; visible = []; treeRows = []
        children = [:]; expanded = []; treeMessages = [:]
        let folder = current; let hidden = showHidden
        analysis.start(root: folder, includeHidden: hidden)
        let worker = Task.detached(priority: .userInitiated) { try FolderEntry.read(folder, showHidden: hidden) }
        listingWorker = worker
        listingTask = Task { [weak self] in
            do {
                let result = try await worker.value
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.entries = result.0; self.truncated = result.1; self.loading = false
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.entries = []; self.error = error.localizedDescription; self.loading = false
            }
        }
    }
    func toggle(_ entry: FolderEntry) {
        guard entry.isFolder else { return }
        if expanded.remove(entry.url) != nil {
            for key in Array(treeTasks.keys) where key == entry.url || key.path.hasPrefix(entry.url.path + "/") { treeTasks.removeValue(forKey: key)?.cancel(); treeWorkers.removeValue(forKey: key)?.cancel(); treeRequests[key] = nil }
            present(); return
        }
        guard entry.url.pathComponents.count - current.pathComponents.count < 64 else { treeMessages[entry.url] = "Tree depth limit reached"; return }
        expanded.insert(entry.url)
        if children[entry.url] != nil { present(); return }
        guard children.values.reduce(0, { $0 + $1.count }) < 10_000 else { treeMessages[entry.url] = "Tree cache limit reached; open this folder to browse"; present(); return }
        let request = UUID(); let generation = generation; let hidden = showHidden
        treeRequests[entry.url] = request; treeMessages[entry.url] = "Loading…"
        let worker = Task.detached(priority: .userInitiated) { try FolderEntry.read(entry.url, showHidden: hidden, limit: 2_000) }
        treeWorkers[entry.url] = worker
        treeTasks[entry.url] = Task { [weak self] in
            do {
                let result = try await worker.value
                guard let self, self.generation == generation, self.treeRequests[entry.url] == request, !Task.isCancelled else { return }
                let remaining = max(0, 10_000 - self.children.values.reduce(0, { $0 + $1.count }))
                self.children[entry.url] = Array(result.0.prefix(remaining))
                self.treeMessages[entry.url] = result.1 || remaining < result.0.count ? "Tree limited; open this folder to see more" : nil
                self.present()
            } catch {
                guard let self, self.generation == generation, self.treeRequests[entry.url] == request, !Task.isCancelled else { return }
                self.treeMessages[entry.url] = error.localizedDescription
            }
            self?.treeTasks[entry.url] = nil; self?.treeWorkers[entry.url] = nil
        }
        present()
    }
    func dispose() {
        generation = UUID(); presentationID = UUID()
        listingTask?.cancel(); listingWorker?.cancel(); presentation?.cancel()
        treeTasks.values.forEach { $0.cancel() }; treeWorkers.values.forEach { $0.cancel() }
        treeTasks = [:]; treeWorkers = [:]; treeRequests = [:]
        analysis.cancel()
    }
    func previewAnalyzedFile(_ url: URL) {
        guard url.path.hasPrefix(current.path == "/" ? "/" : current.path + "/") else { return }
        let canonical = url.resolvingSymlinksInPath().path
        let base = current.resolvingSymlinksInPath().path
        guard canonical.hasPrefix(base == "/" ? "/" : base + "/"), (try? LocalFilePolicy.requireLocal(url)) != nil,
              let v = try? url.resourceValues(forKeys: [.fileSizeKey, .localizedTypeDescriptionKey]) else { return }
        selected = FolderEntry(url: url, name: url.lastPathComponent, isFolder: false, isLink: false, size: Int64(v.fileSize ?? 0), modified: nil, kind: v.localizedTypeDescription ?? "File")
    }
    func moveFocus(_ direction: MoveCommandDirection) {
        let items = mode == "Tree" ? treeRows.map(\.entry) : visible
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.url == focused } ?? -1
        if direction == .left { if mode == "Tree", index >= 0, expanded.contains(items[index].url) { toggle(items[index]) } else { back() }; return }
        if direction == .right { if index >= 0 { if mode == "Tree", items[index].isFolder, !expanded.contains(items[index].url) { toggle(items[index]) } else { enter(items[index]) } }; return }
        let next = max(0, min(items.count - 1, index + (direction == .up ? -1 : 1)))
        focused = items[next].url
    }
    func openFocused() { if let url = focused, let entry = (mode == "Tree" ? treeRows.map(\.entry) : visible).first(where: { $0.url == url }) { enter(entry) } }
    func enter(_ entry: FolderEntry) { focused = entry.url; if entry.isFolder { load(entry.url) } else { selected = entry } }
    func back() { if selected != nil { selected = nil } else if current != root { load(current.deletingLastPathComponent()) } }
    deinit { listingTask?.cancel(); listingWorker?.cancel(); presentation?.cancel(); treeTasks.values.forEach { $0.cancel() }; treeWorkers.values.forEach { $0.cancel() } }
}
