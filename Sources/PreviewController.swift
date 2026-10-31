import AppKit
import SwiftUI
import Quartz

@objc(PeekKitFolderPreviewController)
final class PreviewController: NSViewController, QLPreviewingController {
    private var scopedURL: URL?
    private var accessActive = false
    private var folderModel: FolderModel?
    override func loadView() { view = NSView(frame: NSRect(x: 0,y: 0,width: 880,height: 600)) }
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        folderModel?.dispose()
        children.forEach { $0.view.removeFromSuperview(); $0.removeFromParent() }
        if accessActive, let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
        scopedURL = url; accessActive = url.startAccessingSecurityScopedResource()
        let model = FolderModel(root: url)
        folderModel = model
        let content: AnyView = ArchiveReader.recognizes(url) ? AnyView(ArchiveBrowser(url:url)) : AnyView(FolderBrowser(model:model))
        let host = NSHostingController(rootView: content)
        // Quick Look owns the preview size; folder content must not shrink its host.
        host.sizingOptions = []
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),host.view.topAnchor.constraint(equalTo: view.topAnchor),host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        preferredContentSize = NSSize(width: 880,height: 600)
        handler(nil)
    }
    override func viewWillAppear() {
        if !accessActive, let scopedURL { accessActive = scopedURL.startAccessingSecurityScopedResource() }
        super.viewWillAppear()
    }
    override func viewWillDisappear() {
        folderModel?.dispose()
        if accessActive, let scopedURL { scopedURL.stopAccessingSecurityScopedResource(); accessActive = false }
        super.viewWillDisappear()
    }
    deinit { if accessActive { scopedURL?.stopAccessingSecurityScopedResource() } }
}
