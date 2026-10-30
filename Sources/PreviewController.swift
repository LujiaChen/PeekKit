import AppKit
import SwiftUI
import Quartz

@objc(PeekKitFolderPreviewController)
final class PreviewController: NSViewController, QLPreviewingController {
    private var scopedURL: URL?
    private var folderModel: FolderModel?
    override func loadView() { view = NSView(frame: NSRect(x: 0,y: 0,width: 880,height: 600)) }
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        folderModel?.dispose()
        children.forEach { $0.view.removeFromSuperview(); $0.removeFromParent() }
        if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }; scopedURL = nil
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        let model = FolderModel(root: url)
        folderModel = model
        let host = NSHostingController(rootView: FolderBrowser(model: model))
        // Quick Look owns the preview size; folder content must not shrink its host.
        host.sizingOptions = []
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),host.view.topAnchor.constraint(equalTo: view.topAnchor),host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        preferredContentSize = NSSize(width: 880,height: 600)
        handler(nil)
    }
    override func viewWillDisappear() {
        folderModel?.dispose()
        super.viewWillDisappear()
    }
    deinit { scopedURL?.stopAccessingSecurityScopedResource() }
}
