import AppKit
import WebKit

final class SetupWindow: NSWindow {
    static let size = NSSize(width: 1200, height: 860)
    static let topInset: CGFloat = 80
    /// Matches --bg in app.css so the window never flashes a different colour before the page paints.
    static let background = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x10 / 255, green: 0x13 / 255, blue: 0x1a / 255, alpha: 1)
            : NSColor(srgbRed: 0xee / 255, green: 0xf1 / 255, blue: 0xf6 / 255, alpha: 1)
    }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Respect the requested frame even when the screen is shorter than the window.
        frameRect
    }
    static func initialFrame(screen: NSRect) -> NSRect {
        NSRect(x: screen.minX + 100, y: screen.maxY - topInset - size.height, width: size.width, height: size.height)
    }
}

/// An invisible grab handle in the titlebar. The page runs edge to edge under the traffic lights and
/// WebKit takes every mouse-down, so this is what lets the window be dragged. It draws nothing.
private final class DragStrip: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var engine: SetupEngine!
    var busy = false
    var diskScan: DiskScan?
    var diskCache = DiskCache()
    var diskCacheURL: URL { engine.support.appendingPathComponent("disk-cache.json") }
    var lastLog = "Choose a check or setup action. Results appear here."
    let defaults = UserDefaults.standard
    var webRoot: URL { engine.resources.appendingPathComponent("Web").standardizedFileURL }
    var completed: [String] { defaults.stringArray(forKey: "completed") ?? [] }
    var selected: [String] { defaults.stringArray(forKey: "selected") ?? engine.settings.filter { !$0.protected }.map(\.id) }
    var shellURL: URL { URL(fileURLWithPath: defaults.string(forKey: "shellFolder") ?? ProcessInfo.processInfo.environment["ZDOTDIR"] ?? NSHomeDirectory()).appendingPathComponent(".zshrc") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ArfanReset1")
            engine = try SetupEngine(resources: Bundle.main.resourceURL!, support: support)
            if let data = try? Data(contentsOf: support.appendingPathComponent("last-run.txt")) { lastLog = String(decoding: data, as: UTF8.self) }
            diskCache = DiskCache(url: support.appendingPathComponent("disk-cache.json"))
            diskScan = diskCache.scans[defaults.string(forKey: "diskPath") ?? ""] ?? diskCache.scans[DiskUsage.home]
        } catch {
            let alert = NSAlert(); alert.messageText = "ArfanReset1 could not load its bundled resources"; alert.informativeText = error.localizedDescription; alert.runModal(); NSApp.terminate(nil); return
        }
        let menu = NSMenu()
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "About ArfanReset1", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit ArfanReset1", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(withTitle: title, action: action, keyEquivalent: key) }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; menu.addItem(editItem)
        NSApp.mainMenu = menu
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "reset1")
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self; web.uiDelegate = self
        let setupWindow = SetupWindow(contentRect: NSRect(origin: .zero, size: SetupWindow.size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window = setupWindow
        window.title = "ArfanReset1"; window.minSize = NSSize(width: 650, height: 650)
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.backgroundColor = SetupWindow.background
        web.underPageBackgroundColor = SetupWindow.background
        window.isReleasedWhenClosed = false
        // The web view stays the content view itself; nesting it leaves WebKit's remote layer uncomposited.
        window.contentView = web
        let strip = NSTitlebarAccessoryViewController()
        strip.layoutAttribute = .top
        strip.view = DragStrip(frame: NSRect(x: 0, y: 0, width: SetupWindow.size.width, height: 28))
        window.addTitlebarAccessoryViewController(strip)
        // Total window frame in macOS logical points; top-left measured from the main screen.
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1440)
        window.setFrame(SetupWindow.initialFrame(screen: screen), display: true)
        web.loadFileURL(webRoot.appendingPathComponent("index.html"), allowingReadAccessTo: webRoot)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--window-selftest") {
            DispatchQueue.main.async {
                let target = SetupWindow.initialFrame(screen: screen)
                let actual = self.window.frame
                print("Window frame: \(Int(actual.width))×\(Int(actual.height)), top-left \(Int(actual.minX - screen.minX)),\(Int(screen.maxY - actual.maxY))")
                if actual != target { fputs("Window frame did not match requested placement\n", stderr); exit(1) }
                let frameView = self.window.contentView!.superview!
                func hit(_ x: CGFloat, _ y: CGFloat) -> String { frameView.hitTest(NSPoint(x: x, y: actual.height - y)).map { String(describing: type(of: $0)) } ?? "none" }
                print("Titlebar hits: close button \(hit(20, 14)), empty edge \(hit(640, 14)), content \(hit(640, 70))")
                if hit(640, 14) != "DragStrip" || hit(640, 70) == "DragStrip" { fputs("Drag strip does not cover exactly the titlebar\n", stderr); exit(1) }
                print("WINDOW SELFTEST OK"); NSApp.terminate(nil)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !busy }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if busy {
            let alert = NSAlert(); alert.messageText = "Stop the current setup action and quit?"
            alert.informativeText = "Completed preference changes remain saved. You can restore the last backup when you reopen the app."
            alert.addButton(withTitle: "Keep running"); alert.addButton(withTitle: "Stop and quit")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
            engine.runner.cancel()
        }
        return .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
    func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]), let text = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.receive(\(text))", completionHandler: nil)
    }
    func state() {
        let encoder = JSONEncoder()
        func json<T: Encodable>(_ value: T) -> Any { (try? JSONSerialization.jsonObject(with: encoder.encode(value))) ?? [] }
        send(["type": "state", "settings": json(engine.settings), "installers": json(engine.installers), "guides": json(engine.guides), "selected": selected, "completed": completed, "busy": busy, "log": lastLog, "disk": diskScan.map { json($0) } ?? NSNull(), "diskSaved": Array(diskCache.scans.keys), "shellPath": shellURL.path, "hasBackup": FileManager.default.fileExists(atPath: engine.backupURL.path), "system": "\(ProcessInfo.processInfo.hostName) · \(ProcessInfo.processInfo.operatingSystemVersionString)"])
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { state() }
    func job(_ title: String, work: @escaping () throws -> String) {
        guard !busy else { return }
        busy = true; engine.runner.reset(); lastLog = "Running: \(title)…"; state()
        DispatchQueue.global(qos: .userInitiated).async {
            let output: String
            do { output = try work() } catch { output = "Action stopped or failed: \(error.localizedDescription)" }
            DispatchQueue.main.async {
                self.busy = false; self.lastLog = "\(title) · \(Date().formatted())\n\n" + output
                try? FileManager.default.createDirectory(at: self.engine.support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try? Data(self.lastLog.utf8).write(to: self.engine.support.appendingPathComponent("last-run.txt"), options: .atomic)
                self.state()
            }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.standardizedFileURL == webRoot.appendingPathComponent("index.html"),
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action == "ready" { state(); return }
        if action == "cancel" { engine.runner.cancel(); return }
        if action == "copyLog" { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lastLog, forType: .string); send(["type": "notice", "text": "Run log copied"]); return }
        guard !busy else { return }
        let section = body["section"] as? String ?? "defaults"
        let chosen = engine.settings.filter { selected.contains($0.id) && $0.section == section }
        switch action {
        case "select":
            guard let ids = body["ids"] as? [String] else { return }
            let valid = Set(engine.settings.map(\.id))
            defaults.set(ids.filter { valid.contains($0) }, forKey: "selected"); state()
        case "complete":
            guard let id = body["id"] as? String, ["clt", "tools", "brew", "defaults", "gestures", "shell"].contains(id), let value = body["value"] as? Bool else { return }
            var done = Set(completed); if value { done.insert(id) } else { done.remove(id) }
            defaults.set(done.sorted(), forKey: "completed"); state()
        case "check": job("Check preferences") { try self.engine.check(chosen) }
        case "apply": job("Apply preferences") { try self.engine.apply(chosen) }
        case "restore": job("Restore preferences") { try self.engine.restore() }
        case "tools": job("Check this Mac") { try self.engine.tools() }
        case "clt": job("Command Line Tools") {
            let check = try self.engine.runner.run("/usr/bin/xcode-select", ["-p"])
            if check.code == 0 { return "Already installed: " + check.output }
            let result = try self.engine.runner.run("/usr/bin/xcode-select", ["--install"])
            return result.output + "\n\nFinish the Apple installer dialog, then use Check this Mac to verify installation."
        }
        case "disk":
            let requested = body["path"] as? String ?? DiskUsage.home
            guard DiskUsage.isAllowed(requested) else { send(["type": "notice", "text": "Disk usage only reads inside your home folder."]); return }
            defaults.set(requested, forKey: "diskPath")
            // A saved scan opens instantly; only Refresh (or a folder never scanned) runs du.
            if body["refresh"] as? Bool != true, let saved = diskCache.scans[requested] { diskScan = saved; state(); return }
            job("Disk usage") {
                let scan = try self.engine.diskScan(path: requested)
                DispatchQueue.main.sync {
                    self.diskScan = scan
                    self.diskCache.store(scan)
                    try? self.diskCache.save(to: self.diskCacheURL)
                }
                let skipped = scan.unreadable > 0 ? "\n\(scan.unreadable) items could not be read, so totals may be low." : ""
                return "Read-only scan of \(scan.path)\n\(scan.entries.count + scan.moreCount) items · \(ByteCountFormatter.string(fromByteCount: Int64(scan.bytes), countStyle: .file)). Nothing was changed.\(skipped)"
            }
        case "diskReveal":
            guard let path = body["path"] as? String, DiskUsage.isAllowed(path) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case "shellCheck":
            let target = shellURL
            job("Check Zsh") {
                let exists = FileManager.default.fileExists(atPath: target.path)
                let syntax = exists ? try self.engine.runner.run("/bin/zsh", ["-n", target.path]) : CommandResult(code: 0, output: "No existing .zshrc; setup will create it.")
                let original = exists ? try String(contentsOf: target, encoding: .utf8) : ""
                let proposed = try ShellSetup.updated(original, config: self.engine.shell)
                return "Target: \(target.path)\nSyntax: \(syntax.code == 0 ? "OK" : "FAILED")\n\(syntax.output)\n\(proposed == original ? "Setup already present." : "Setup would update one marked block; existing files will be backed up.")\n\nProposed .zshrc:\n\(proposed)"
            }
        case "shellApply":
            let target = shellURL
            job("Set up Zsh") { try ShellSetup.install(at: target, config: self.engine.shell, runner: self.engine.runner) }
        case "shellFolder":
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.message = "Choose the folder containing your .zshrc (HOME or ZDOTDIR)."
            if panel.runModal() == .OK, let url = panel.url { defaults.set(url.path, forKey: "shellFolder"); state() }
        case "restart": job("Restart Finder & Dock") {
            let finder = try self.engine.runner.run("/usr/bin/killall", ["Finder"])
            let dock = try self.engine.runner.run("/usr/bin/killall", ["Dock"])
            return "Finder: \(finder.code == 0 ? "Restart requested" : finder.output)\nDock: \(dock.code == 0 ? "Restart requested" : dock.output)"
        }
        case "settings":
            guard let id = body["id"] as? String else { return }
            let paths = ["privacy": "Privacy_AllFiles", "zoom": "Zoom", "keyboard": "Keyboard", "trackpad": "com.apple.Trackpad-Settings.extension", "storage": "com.apple.settings.Storage"]
            if let path = paths[id], let url = URL(string: "x-apple.systempreferences:" + (id == "privacy" ? "com.apple.preference.security?" : ["zoom", "keyboard"].contains(id) ? "com.apple.preference.universalaccess?" : "") + path) { NSWorkspace.shared.open(url) }
        case "reveal":
            try? FileManager.default.createDirectory(at: engine.support, withIntermediateDirectories: true)
            NSWorkspace.shared.open(engine.support)
        case "installer":
            guard let id = body["id"] as? String, let installer = engine.installers.first(where: { $0.id == id }) else { return }
            do {
                let folder = engine.support.appendingPathComponent("Terminal")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let file = folder.appendingPathComponent(installer.id + "-" + UUID().uuidString + ".command")
                let script = "#!/bin/zsh\nset -euo pipefail\n# ArfanReset1 · \(installer.name)\n" + installer.command + "\nprint '\nInstaller finished. Return to ArfanReset1 and run Check this Mac.'\nread '?Press Return to close this session.'\n"
                try script.write(to: file, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
                let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    DispatchQueue.main.async {
                        self.lastLog = error.map { "Could not open Terminal: " + $0.localizedDescription } ?? "Opened \(installer.name) in Terminal. Finish its prompts, then check this Mac. Installation has not been verified.\n\nScript: \(file.path)"
                        self.state()
                    }
                }
            } catch { lastLog = error.localizedDescription; state() }
        default: send(["type": "notice", "text": "Unknown action"])
        }
    }
    func allowed(_ url: URL) -> Bool {
        url.isFileURL && url.resolvingSymlinksInPath().path.hasPrefix(webRoot.resolvingSymlinksInPath().path + "/")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if allowed(url) || (url.absoluteString == "about:blank" && navigationAction.targetFrame?.isMainFrame == false) { decisionHandler(.allow); return }
        if ["https", "http"].contains(url.scheme ?? ""), navigationAction.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }
}

@main
enum ArfanReset1 {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            do { try SelfTests.run(); print("SELFTEST OK") } catch { fputs("SELFTEST FAILED: \(error)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
