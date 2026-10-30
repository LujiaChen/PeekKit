import Foundation
import Combine

@MainActor final class FolderAnalysisModel: ObservableObject {
    @Published private(set) var snapshot: FolderAnalysisSnapshot?
    @Published private(set) var stopping = false
    private var task: Task<Void, Never>?
    private var cancellation: AnalysisCancellation?
    private var generation = UUID()
    private(set) var options = FolderAnalysisOptions()

    func start(root: URL, includeHidden: Bool) {
        cancel()
        options.includeHidden = includeHidden
        let request = options
        let id = UUID()
        generation = id
        let token = AnalysisCancellation()
        cancellation = token
        stopping = false
        snapshot = FolderAnalysisSnapshot(root: root, includeHidden: includeHidden)
        task = Task.detached(priority: .utility) { [weak self] in
            let final = FolderAnalyzer.scan(root: root, options: request, cancellation: token) { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == id, self.snapshot?.state == .scanning else { return }
                    self.snapshot = update
                }
            }
            await self?.finish(final, id: id)
        }
    }
    private func finish(_ result: FolderAnalysisSnapshot, id: UUID) {
        guard generation == id else { return }
        snapshot = result
        stopping = false
        task = nil
        cancellation = nil
    }
    func stop() {
        guard snapshot?.state == .scanning else { return }
        stopping = true
        cancellation?.cancel()
        task?.cancel()
    }
    func cancel() {
        generation = UUID()
        cancellation?.cancel()
        task?.cancel()
        cancellation = nil
        task = nil
        stopping = false
    }
    func restart() {
        guard let snapshot else { return }
        start(root: snapshot.root, includeHidden: snapshot.includeHidden)
    }
    deinit { cancellation?.cancel(); task?.cancel() }
}
