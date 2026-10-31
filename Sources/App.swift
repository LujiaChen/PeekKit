import AppKit
import SwiftUI
import Quartz

@main struct PeekKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var selfTest: RendererSelfTest?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--appearance"), args.count > i+1 { NSApp.appearance = NSAppearance(named: args[i+1] == "light" ? .aqua : .darkAqua) }
        if let i = args.firstIndex(of: "--quicklook-test"), args.count > i+1 {
            let preview = QLPreviewView(frame:NSRect(x:0,y:0,width:900,height:680),style:.normal)!
            let window = NSWindow(contentRect:preview.frame,styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            window.title = "PeekKit — System Quick Look Test"; window.contentView = preview; show(window)
            preview.previewItem = URL(fileURLWithPath:args[i+1]) as NSURL
            return
        }
        if let i = args.firstIndex(of: "--self-test"), args.count > i+1 {
            selfTest = RendererSelfTest(output: URL(fileURLWithPath: args[i+1])); selfTest?.run(); return
        }
        if let i = args.firstIndex(of: "--preview"), args.count > i+1 { preview(URL(fileURLWithPath: args[i+1])); return }
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:620,height:570),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "PeekKit"
        window.contentView = NSHostingView(rootView: WelcomeView(choose: choose, demo: { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.url(forResource:"Welcome",withExtension:"md")!]) }))
        show(window)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func choose() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.prompt = "Preview"
        if panel.runModal() == .OK, let url = panel.url { preview(url) }
    }
    func show(_ window: NSWindow) { window.isReleasedWhenClosed = false; window.center(); window.makeKeyAndOrderFront(nil); windows.append(window); NSApp.activate(ignoringOtherApps:true)
        let args = CommandLine.arguments
        if let index = args.firstIndex(of:"--snapshot"), args.count > index+1 {
            let path = args[index+1]
            DispatchQueue.main.asyncAfter(deadline:.now()+4) {
                guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { NSApp.terminate(nil); return }
                view.cacheDisplay(in:view.bounds,to:bitmap)
                if let data = bitmap.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:path)) }
                NSApp.terminate(nil)
            }
        }
    }
    func preview(_ url: URL) {
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:900,height:680),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "\(url.lastPathComponent) — PeekKit"; window.minSize = NSSize(width:620,height:440)
        if CommandLine.arguments.contains("--inspector") {
            window.contentView = NSHostingView(rootView:FileInspectorView(url:url))
        } else if (try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true {
            let model = FolderModel(root:url, preferences:CommandLine.arguments.contains("--snapshot") ? UserDefaults(suiteName:"PeekKit.Screenshot")! : .standard)
            if CommandLine.arguments.contains("--list-demo") { model.mode = "List" }
            window.contentView = NSHostingView(rootView: FolderBrowser(model:model))
        } else if ArchiveReader.recognizes(url) {
            window.contentView = NSHostingView(rootView:ArchiveBrowser(url:url))
        } else if isMarkdown(url) {
            window.contentView = NSHostingView(rootView: MarkdownContent(url:url))
        } else {
            let v = try? url.resourceValues(forKeys:[.fileSizeKey,.localizedTypeDescriptionKey,.isSymbolicLinkKey])
            let entry = FolderEntry(url:url,name:url.lastPathComponent,isFolder:false,isLink:v?.isSymbolicLink == true,size:Int64(v?.fileSize ?? 0),modified:nil,kind:v?.localizedTypeDescription ?? "File")
            window.contentView = NSHostingView(rootView: FileDetail(entry:entry))
        }
        show(window)
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { if CommandLine.arguments.contains("--snapshot") { sender.reply(toOpenOrPrint:.success); return }; filenames.forEach { preview(URL(fileURLWithPath:$0)) }; sender.reply(toOpenOrPrint:.success) }
}
struct WelcomeView: View {
    let choose: () -> Void
    let demo: () -> Void
    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width:92,height:92)
            VStack(spacing:8) { Text("A closer look, with Space.").font(.system(size:28,weight:.bold)); Text("Folders and Markdown, together.").font(.title3).foregroundStyle(.secondary) }
            HStack(alignment:.top,spacing:22) {
                feature("folder.fill","Explore folders","Browse a grid, list or tree. Analyze storage and preview images, PDFs, text, and Markdown.")
                feature("doc.richtext","Read Markdown","Formatted headings, tables, code, and checklists. Switch to the original source.")
            }
            VStack(alignment:.leading,spacing:12) {
                Label("Enable PeekKit Folder and PeekKit Markdown in Quick Look.",systemImage:"1.circle.fill")
                Label("Select a folder or Markdown file in Finder and press Space.",systemImage:"2.circle.fill")
            }.font(.callout).frame(maxWidth:.infinity,alignment:.leading).padding(18).background(.quaternary.opacity(0.45),in:RoundedRectangle(cornerRadius:14))
            HStack(spacing:12) {
                Button("Quick Look Settings") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!) }.buttonStyle(.borderedProminent)
                Button("Preview…",action:choose)
                Button("Try in Finder",action:demo)
            }
            Text("Works locally. No account or background app required.").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width:620,height:570)
    }
    func feature(_ symbol:String,_ title:String,_ detail:String) -> some View {
        VStack(alignment:.leading,spacing:8) { Label(title,systemImage:symbol).font(.headline).foregroundStyle(.blue); Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }.frame(maxWidth:.infinity,alignment:.topLeading)
    }
}
