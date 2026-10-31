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
    private let pageField = NSTextField(string: "1")
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
        pageField.alignment = .right; pageField.target = self; pageField.action = #selector(goToPage)
        pageField.setAccessibilityLabel("PDF page number"); pageField.toolTip = "Enter a page number and press Return"
        pageField.widthAnchor.constraint(equalToConstant: 55).isActive = true
        countLabel.setAccessibilityLabel("PDF page count")
        func button(_ title: String, _ action: Selector, _ label: String) -> NSButton {
            let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded
            b.setAccessibilityLabel(label); b.toolTip = label; return b
        }
        let toolbar = NSStackView(views: [button("‹", #selector(previous), "Previous PDF page"), pageField, countLabel, button("Go", #selector(goToPage), "Go to PDF page"),
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
        pdfView.document = document; sourceLease = source; pdfView.autoScales = true; updatePage()
    }
    private func updatePage() {
        let count = pdfView.document?.pageCount ?? 0
        countLabel.stringValue = "of \(count)"
        if let page = pdfView.currentPage, let document = pdfView.document { pageField.integerValue = document.index(for: page) + 1 }
        else { pageField.integerValue = 0 }
    }
    @objc func goToPage() { go(toPage: pageField.integerValue) }
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
