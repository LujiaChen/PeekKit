import SwiftUI

struct FileInspectorView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var result: PeekKitInspection?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File Information").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let result {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    row("Name", result.name)
                    row("Extension", result.fileExtension.isEmpty ? "—" : result.fileExtension)
                    row("Type from extension", result.type ?? (result.isSymlink ? "Symbolic link" : "Unavailable"))
                    row("Size", fileSize(result.logicalBytes))
                    row("Allocated blocks", fileSize(result.allocatedBytes))
                    row("Created", result.created.formatted())
                    row("Modified", result.modified.formatted())
                    row("Last accessed", result.accessed.formatted())
                    row("Permissions", result.permissions)
                    row("Path", result.path)
                }.textSelection(.enabled)
                Text("Allocated blocks are not necessarily exclusive or reclaimable space.").font(.caption).foregroundStyle(.secondary)
            } else if let error {
                Text(error).foregroundStyle(.secondary).textSelection(.enabled)
            } else { ProgressView("Reading metadata…") }
        }
        .padding(20).frame(minWidth: 500, alignment: .leading)
        .task(id: url) {
            result = nil; error = nil
            let worker = Task.detached(priority: .userInitiated) { try PeekKitInspection.read(url) }
            do {
                let value = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled else { return }
                result = value
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow { Text(title).foregroundStyle(.secondary); Text(value).lineLimit(2) }
    }
}
