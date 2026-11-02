import SwiftUI
import PDFKit

/// PDFKit draws visible pages; the toolbar never walks/rasterizes the document.
struct PDFContent: NSViewControllerRepresentable {
    let document: PDFDocument
    var source: FileBackedPDF? = nil
    func makeNSViewController(context: Context) -> PDFViewerController { PDFViewerController(document: document, source: source) }
    func updateNSViewController(_ controller: PDFViewerController, context: Context) { controller.show(document, source: source) }
    static func dismantleNSViewController(_ controller: PDFViewerController, coordinator: ()) { controller.show(nil) }
}

final class PDFViewerController: NSViewController {
    let pdfView = PDFView()
    private let pagePicker = NSPopUpButton(frame:.zero,pullsDown:true)
    private var menuSource: PDFPageMenu?
    private let countLabel = NSTextField(labelWithString: "")
    private var initialDocument: PDFDocument?
    private var sourceLease: FileBackedPDF?
    private var tokens: [NSObjectProtocol] = []
    init(document: PDFDocument, source: FileBackedPDF? = nil) { initialDocument = document; sourceLease = source; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func loadView() {
        let root = NSView(); view = root
        pdfView.displayMode = .singlePageContinuous; pdfView.displayDirection = .vertical
        pdfView.autoScales = true; pdfView.minScaleFactor = 0.1; pdfView.maxScaleFactor = 8
        pdfView.setAccessibilityLabel("PDF pages")
        pagePicker.setAccessibilityLabel("Choose PDF page")
        pagePicker.toolTip = "Choose a page from the menu. Finder may reserve keyboard input."
        pagePicker.widthAnchor.constraint(greaterThanOrEqualToConstant:65).isActive = true
        countLabel.setAccessibilityLabel("PDF page count")
        func button(_ title: String, _ action: Selector, _ label: String) -> NSButton {
            let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded
            b.setAccessibilityLabel(label); b.toolTip = label; return b
        }
        let toolbar = NSStackView(views: [button("‹", #selector(previous), "Previous PDF page"), pagePicker, countLabel,
            button("›", #selector(next), "Next PDF page"), button("−", #selector(zoomOut), "Zoom out PDF"),
            button("+", #selector(zoomIn), "Zoom in PDF"), button("Fit", #selector(fit), "Fit PDF to window")])
        toolbar.spacing = 8; toolbar.orientation = .horizontal
        for v in [toolbar, pdfView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 6), toolbar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            pdfView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 6), pdfView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: root.trailingAnchor), pdfView.bottomAnchor.constraint(equalTo: root.bottomAnchor)])
        tokens.append(NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in self?.updatePage() })
        show(initialDocument, source: sourceLease); initialDocument = nil
    }
    func show(_ document: PDFDocument?, source: FileBackedPDF? = nil) {
        guard isViewLoaded else { initialDocument = document; return }
        guard pdfView.document !== document else { return } // SwiftUI updates must not reset scroll/zoom.
        pdfView.document = document; sourceLease = source; pdfView.autoScales = true
        if let document, document.pageCount > 0 {
            menuSource = PDFPageMenu(owner:self,range:1...document.pageCount,root:true)
            let menu = NSMenu(); menu.delegate = menuSource; pagePicker.menu = menu; menu.update()
        } else { pagePicker.menu = nil; menuSource = nil }
        pagePicker.isEnabled = document != nil
        updatePage()
    }
    private func updatePage() {
        let count = pdfView.document?.pageCount ?? 0
        countLabel.stringValue = "of \(count)"
        if let page = pdfView.currentPage, let document = pdfView.document { pagePicker.title = String(document.index(for: page) + 1) }
        else { pagePicker.title = "—" }
    }
    @objc func choosePage(_ sender:NSMenuItem) { go(toPage:sender.tag) }
    func go(toPage number: Int) {
        guard let document = pdfView.document, let page = document.page(at: max(1, min(document.pageCount, number)) - 1) else { updatePage(); return }
        pdfView.go(to: page); updatePage()
    }
    @objc func previous() { pdfView.goToPreviousPage(nil) }
    @objc func next() { pdfView.goToNextPage(nil) }
    @objc func zoomIn() { pdfView.autoScales = false; pdfView.zoomIn(nil) }
    @objc func zoomOut() { pdfView.autoScales = false; pdfView.zoomOut(nil) }
    @objc func fit() { pdfView.autoScales = true }
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}

/// Native menus remain usable when the Finder host reserves text-field keys.
/// Lazily partition ranges so even huge documents never create more than 101
/// menu items at one level; submenus are populated only when opened.
final class PDFPageMenu: NSObject, NSMenuDelegate {
    private weak var owner: PDFViewerController?
    private let range: ClosedRange<Int>
    private let root: Bool
    init(owner:PDFViewerController,range:ClosedRange<Int>,root:Bool = false) { self.owner = owner; self.range = range; self.root = root }
    func menuNeedsUpdate(_ menu:NSMenu) {
        // Accessibility may query repeatedly while a menu is being tracked.
        // Preserve item identities; rebuilding here invalidates active choices.
        guard menu.items.isEmpty else { return }
        guard let owner, owner.pdfView.document != nil else { return }
        if root {
            let page = owner.pdfView.currentPage.map { (owner.pdfView.document?.index(for:$0) ?? 0)+1 } ?? 1
            menu.addItem(NSMenuItem(title:String(page),action:nil,keyEquivalent:""))
        }
        let count = range.upperBound-range.lowerBound+1
        let step = max(1,count/100 + (count%100 == 0 ? 0:1))
        var start = range.lowerBound
        while start <= range.upperBound {
            let end = start + min(step-1,range.upperBound-start)
            if start == end {
                let item = NSMenuItem(title:"Page \(start)",action:#selector(PDFViewerController.choosePage(_:)),keyEquivalent:"")
                item.tag = start; item.target = owner; menu.addItem(item)
            } else {
                let item = NSMenuItem(title:"\(start)–\(end)",action:nil,keyEquivalent:"")
                let submenu = NSMenu(title:item.title)
                let delegate = PDFPageMenu(owner:owner,range:start...end)
                item.representedObject = delegate // NSMenu.delegate is weak.
                submenu.delegate = delegate; item.submenu = submenu; menu.addItem(item)
            }
            if end == range.upperBound { break }; start = end+1
        }
    }
}
