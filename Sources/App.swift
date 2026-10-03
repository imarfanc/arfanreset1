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
    var preferenceResults: [String: PreferenceResult] = [:]
    var toolResults: [String: ToolResult] = [:]
    var functionPreview: FunctionPreview?
    var shellPreview: ShellPreview?
    var partialLog = ""
    var busy = false
    var diskScan: DiskScan?
    var diskCache = DiskCache()
    var diskCacheURL: URL { engine.support.appendingPathComponent("disk-cache.json") }
    var lastLog = "Choose a check or setup action. Results appear here."
    var permissions: [Permission]?
    var permissionsCheckedAt: TimeInterval = 0
    let defaults = UserDefaults.standard
    var webRoot: URL { engine.resources.appendingPathComponent("Web").standardizedFileURL }
    var completed: [String] { defaults.stringArray(forKey: "completed") ?? [] }
    var selected: [String] { defaults.stringArray(forKey: "selected") ?? engine.settings.filter { !$0.protected }.map(\.id) }
    /// The option each choice row will apply: the one picked on the page, or the row's default.
    var choices: [String: String] {
        let picked = defaults.dictionary(forKey: "choices") as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: engine.settings.compactMap { row in row.option(picked[row.id]).map { (row.id, $0.id) } })
    }
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
        engine.preferenceResult = { result in DispatchQueue.main.sync { self.preferenceResults[result.id] = result } }
        engine.toolResult = { result in DispatchQueue.main.sync { self.toolResults[result.id] = result } }
        engine.progress = { text in
            DispatchQueue.main.sync {
                self.partialLog = text
                self.lastLog = "Action in progress\n\n" + text
                self.saveLog(); self.state()
            }
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
        // Interface sounds are synthesized with Web Audio; let job-finished chimes play without a fresh click.
        config.mediaTypesRequiringUserActionForPlayback = []
        // Guides are local pages and cannot fetch file:// URLs, so the app hands them the bundled, expanded scripts.
        if let data = try? JSONSerialization.data(withJSONObject: engine.scripts), let scripts = String(data: data, encoding: .utf8) {
            let source = "if (location.pathname.includes('/Web/guides/')) window.RESET1_SCRIPTS = \(scripts);"
            config.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
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
        send(["type": "state", "accessibilityActions": AccessibilityAction.all.map { ["id": $0.id, "name": $0.name, "description": $0.description, "settingsID": $0.settingsID, "path": $0.path, "help": $0.help, "prompt": $0.prompt, "cliCommand": $0.cliCommand(script: engine.scripts[$0.scriptName] ?? ""), "script": engine.scripts[$0.scriptName] ?? ""] }, "functions": json(engine.functions), "functionStatuses": json(ShellFunctions.status(engine.functions, at: shellURL)), "functionPreview": functionPreview.map { json($0) } ?? NSNull(), "preferenceResults": json(preferenceResults), "toolResults": json(toolResults), "shellPreview": shellPreview.map { json($0) } ?? NSNull(), "settings": json(engine.settings), "installers": json(engine.installers), "guides": json(engine.guides), "selected": selected, "choices": choices, "completed": completed, "busy": busy, "log": lastLog, "disk": diskScan.map { json($0) } ?? NSNull(), "permissions": permissions.map { json($0) } ?? NSNull(), "permissionsCheckedAt": permissionsCheckedAt, "diskSaved": Array(diskCache.scans.keys), "shellPath": shellURL.path, "shellFiles": json(ShellSetup.files(for: shellURL)), "hasBackup": FileManager.default.fileExists(atPath: engine.backupURL.path), "system": "\(ProcessInfo.processInfo.hostName) · \(ProcessInfo.processInfo.operatingSystemVersionString)"])
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { state() }
    func saveLog() {
        try? FileManager.default.createDirectory(at: engine.support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? Data(lastLog.utf8).write(to: engine.support.appendingPathComponent("last-run.txt"), options: .atomic)
    }
    func job(_ title: String, work: @escaping () throws -> String) {
        guard !busy else { return }
        busy = true; partialLog = ""; engine.runner.reset(); lastLog = "Running: \(title)…"; state()
        DispatchQueue.global(qos: .userInitiated).async {
            let output: String
            var ok = true
            do { output = try work() } catch { ok = false; output = "Action stopped or failed: \(error.localizedDescription)" }
            // Same marks the log uses: ✕ is a failed item, FAILED a failed syntax check.
            ok = ok && !output.contains("✕") && !output.contains("FAILED")
            DispatchQueue.main.async {
                self.busy = false; self.lastLog = "\(title) · \(Date().formatted())\n\n" + (!ok && !self.partialLog.isEmpty && !output.contains(self.partialLog) ? self.partialLog + "\n\n" : "") + output
                try? FileManager.default.createDirectory(at: self.engine.support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try? Data(self.lastLog.utf8).write(to: self.engine.support.appendingPathComponent("last-run.txt"), options: .atomic)
                self.state()
                self.send(["type": "done", "ok": ok])
            }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.standardizedFileURL == webRoot.appendingPathComponent("index.html"),
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action == "ready" { state(); checkPermissions(); return }
        if action == "cancel" { engine.runner.cancel(); return }
        // The quiet check refreshes the Permissions page without touching the run log, so it may run beside a job.
        if action == "permissions", body["log"] as? Bool != true { checkPermissions(); return }
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
        case "choose":
            guard let id = body["id"] as? String, let option = body["option"] as? String,
                  let row = engine.settings.first(where: { $0.id == id }), row.options?.contains(where: { $0.id == option }) == true else { return }
            var picked = defaults.dictionary(forKey: "choices") as? [String: String] ?? [:]
            picked[id] = option
            defaults.set(picked, forKey: "choices")
            // A row that had a result is read again for its new option, so the badge never describes the old one.
            let checked = preferenceResults[id] != nil
            preferenceResults[id] = nil; state()
            if checked { recheck(row, option: option) }
        case "check":
            let all = engine.settings.filter { $0.section == section }
            let picked = choices
            job("Check preferences") { try self.engine.check(all, choices: picked) }
        case "apply":
            for setting in chosen { preferenceResults[setting.id] = nil }
            let picked = choices
            job("Apply preferences") { try self.engine.apply(chosen, choices: picked) }
        case "restore":
            preferenceResults = [:]
            job("Restore preferences") { try self.engine.restore() }
        case "toolCheck":
            guard let id = body["id"] as? String, let installer = engine.installers.first(where: { $0.id == id }) else { return }
            job("Check \(installer.name)") {
                let result = try self.engine.checkTool(id)
                DispatchQueue.main.sync { self.toolResults[id] = result }
                return result.logEntry(name: installer.name)
            }
        case "tools": job("Check all tools") { try self.engine.tools() }
        case "permissions":
            let target = shellURL
            job("Check permissions") {
                let list = try self.engine.permissions(shell: target, runner: self.engine.runner)
                DispatchQueue.main.sync { self.permissions = list; self.permissionsCheckedAt = Date().timeIntervalSince1970 }
                let mark = ["granted": "✓ Allowed", "missing": "• Needs attention", "unknown": "? Unknown"]
                return "Read-only check · nothing was changed\n\n" + list.map { "\(mark[$0.status] ?? $0.status) · \($0.name)\n  \($0.detail)\n  Used by: \($0.usedBy)" }.joined(separator: "\n")
            }
        case "clt": job("Command Line Tools") {
            let check = try self.engine.runner.run("/usr/bin/xcode-select", ["-p"])
            if check.code == 0 { return "Already installed: " + check.output }
            let result = try self.engine.runner.run("/usr/bin/xcode-select", ["--install"])
            return result.output + "\n\nFinish Apple’s installer dialog, then choose Check installation."
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
                return "Read-only scan of \(scan.path)\n\(scan.itemCount) items · \(ByteCountFormatter.string(fromByteCount: Int64(scan.bytes), countStyle: .file)). Nothing was changed.\(skipped)"
            }
        case "diskReveal":
            guard let path = body["path"] as? String, DiskUsage.isAllowed(path) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case "functionStatus": state()
        case "functionCopy", "functionPreview", "functionApply":
            guard let id = body["id"] as? String, let function = engine.functions.first(where: { $0.id == id }) else { return }
            if action == "functionCopy" {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(function.code, forType: .string)
                send(["type": "notice", "text": "\(function.name) copied. Paste it into your .zshrc."])
                return
            }
            let target = shellURL
            functionPreview = nil
            if action == "functionApply" { shellPreview = nil }
            job(action == "functionPreview" ? "Preview \(function.name)" : "Add \(function.name) to .zshrc") {
                let original = FileManager.default.fileExists(atPath: target.path) ? try String(contentsOf: target, encoding: .utf8) : ""
                let proposed = try ShellFunctions.updated(original, function: function)
                if action == "functionPreview" {
                    let preview = try ShellSetup.previewChange(at: target, original: original, proposed: proposed, runner: self.engine.runner)
                    DispatchQueue.main.sync { self.functionPreview = FunctionPreview(id: id, preview: preview) }
                    return preview.changed ? "Preview is ready on the \(function.name) card. Nothing has changed yet." : "Your .zshrc already has this exact \(function.name). Nothing to change."
                }
                return try ShellSetup.write(at: target, original: original, result: proposed, runner: self.engine.runner)
            }
        case "shellCheck":
            shellPreview = nil; functionPreview = nil
            let target = shellURL
            job("Preview Zsh changes") {
                let preview = try ShellSetup.preview(at: target, config: self.engine.shell, runner: self.engine.runner)
                DispatchQueue.main.sync { self.shellPreview = preview }
                return preview.changed ? "Preview is ready on this page. Nothing has changed yet. Review the added and removed lines, then choose Set up Zsh." : "Your .zshrc already has this setup. Nothing to change."
            }
        case "shellRestore":
            let target = shellURL
            let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
            panel.showsHiddenFiles = true
            panel.directoryURL = target.deletingLastPathComponent().appendingPathComponent("backups")
            panel.message = "Choose a .zshrc.backup- file. Restore saves your current .zshrc first and checks the backup’s syntax."
            panel.prompt = "Restore backup"
            if panel.runModal() == .OK, let backup = panel.url {
                shellPreview = nil; functionPreview = nil
                job("Restore Zsh backup") { try ShellSetup.restore(at: target, from: backup, runner: self.engine.runner) }
            }
        case "shellApply":
            shellPreview = nil; functionPreview = nil
            let target = shellURL
            job("Set up Zsh") { try ShellSetup.install(at: target, config: self.engine.shell, runner: self.engine.runner) }
        case "shellFiles":
            // Only the files Zsh setup touches, looked up by id. Missing ones show their folder instead.
            let files = ShellSetup.files(for: shellURL)
            let chosen = (body["id"] as? String).map { id in files.filter { $0.id == id } } ?? files
            guard !chosen.isEmpty else { return }
            if body["open"] as? Bool == true, let file = chosen.first, file.exists, !file.isFolder {
                NSWorkspace.shared.open([URL(fileURLWithPath: file.path)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), configuration: NSWorkspace.OpenConfiguration())
            } else if chosen.count == 1, let folder = chosen.first, folder.isFolder {
                NSWorkspace.shared.open(URL(fileURLWithPath: folder.path))
            } else {
                let present = chosen.filter(\.exists).map { URL(fileURLWithPath: $0.path) }
                if present.isEmpty { NSWorkspace.shared.open(shellURL.deletingLastPathComponent()) }
                else { NSWorkspace.shared.activateFileViewerSelecting(present) }
            }
        case "shellFolder":
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.message = "Choose the folder containing your .zshrc (HOME or ZDOTDIR)."
            if panel.runModal() == .OK, let url = panel.url { defaults.set(url.path, forKey: "shellFolder"); shellPreview = nil; functionPreview = nil; state(); checkPermissions() }
        case "restart": job("Restart Finder & Dock") {
            let finder = try self.engine.runner.run("/usr/bin/killall", ["Finder"])
            let dock = try self.engine.runner.run("/usr/bin/killall", ["Dock"])
            return "Finder: \(finder.code == 0 ? "Restart requested" : finder.output)\nDock: \(dock.code == 0 ? "Restart requested" : dock.output)"
        }
        case "accessibilityCopyCLI", "accessibilityRunCLI", "accessibilityCopyScript", "accessibilityRunScript", "accessibilityCopyPrompt", "accessibilityCodex":
            guard let id = body["id"] as? String, let item = AccessibilityAction.all.first(where: { $0.id == id }) else { return }
            if action == "accessibilityCopyCLI" || action == "accessibilityCopyPrompt" || action == "accessibilityCopyScript" {
                let text = action == "accessibilityCopyCLI" ? item.cliCommand(script: engine.scripts[item.scriptName] ?? "") : action == "accessibilityCopyPrompt" ? item.prompt : engine.scripts[item.scriptName] ?? ""
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                send(["type": "notice", "text": action == "accessibilityCopyPrompt" ? "Prompt copied. In Codex, choose GPT-6 Luna, paste and send." : action == "accessibilityCopyCLI" ? "Command copied. Paste it into Terminal to run it." : "Script copied. Paste it into Terminal to run it."])
            } else if action == "accessibilityCodex" {
                if !NSWorkspace.shared.open(AccessibilityAction.codexURL(for: item)) {
                    send(["type": "notice", "text": "Could not open Codex. Install or open Codex, then use Copy prompt."])
                }
            } else {
                do {
                    guard let script = engine.scripts[item.scriptName], !script.isEmpty else { throw SetupError.message("Bundled script missing") }
                    let folder = engine.support.appendingPathComponent("Terminal")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let file = folder.appendingPathComponent(item.id + "-" + UUID().uuidString + ".command")
                    let runScript = action == "accessibilityRunCLI" ? item.cliCommand(script: script) : script
                    let command = "#!/bin/bash\n" + runScript + "\nprintf '\nFinished. Press Return to close.'\nread -r\n"
                    try command.write(to: file, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
                    NSWorkspace.shared.open([file], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration()) { _, error in
                        DispatchQueue.main.async {
                            self.lastLog = error.map { "Could not open Terminal: " + $0.localizedDescription } ?? "Opened the \(action == "accessibilityRunCLI" ? "Codex CLI session" : "AppleScript") for \(item.name) in Terminal. Read the result there. ArfanReset1 cannot see the switch, so confirm it in System Settings."
                            self.state()
                        }
                    }
                } catch { lastLog = error.localizedDescription; state() }
            }
        case "settings":
            guard let id = body["id"] as? String else { return }
            if id == "speech" {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Speak")!
                if !NSWorkspace.shared.open(url) { send(["type": "notice", "text": "Open System Settings → Accessibility → Read & Speak, then turn on Speak selection."]) }
                return
            }
            let paths = ["privacy": "Privacy_AllFiles", "zoom": "Zoom", "keyboard": "Keyboard", "trackpad": "com.apple.Trackpad-Settings.extension", "storage": "com.apple.settings.Storage", "users": "com.apple.Users-Groups-Settings.extension"]
            if let path = paths[id], let url = URL(string: "x-apple.systempreferences:" + (id == "privacy" ? "com.apple.preference.security?" : ["zoom", "keyboard"].contains(id) ? "com.apple.preference.universalaccess?" : "") + path) { NSWorkspace.shared.open(url) }
        case "reveal":
            try? FileManager.default.createDirectory(at: engine.support, withIntermediateDirectories: true)
            NSWorkspace.shared.open(engine.support)
        case "installer":
            guard let id = body["id"] as? String, let installer = engine.installers.first(where: { $0.id == id }) else { return }
            do {
                toolResults[id] = nil
                let folder = engine.support.appendingPathComponent("Terminal")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let file = folder.appendingPathComponent(installer.id + "-" + UUID().uuidString + ".command")
                let script = "#!/bin/zsh\nset -euo pipefail\n# ArfanReset1 · \(installer.name)\n" + installer.command + "\nprint '\nInstaller finished. Go back to ArfanReset1 and choose Check installation.'\nread '?Press Return to close this session.'\n"
                try script.write(to: file, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
                let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    DispatchQueue.main.async {
                        self.lastLog = error.map { "Could not open Terminal: " + $0.localizedDescription } ?? "Opened the \(installer.name) installer in Terminal. Finish its prompts there, then choose Check installation. Nothing is verified until you check.\n\nScript: \(file.path)"
                        self.state()
                    }
                }
            } catch { lastLog = error.localizedDescription; state() }
        default: send(["type": "notice", "text": "Unknown action"])
        }
    }
    /// Read only, quiet, and on its own runner like checkPermissions: one row's keys, without touching the run log.
    func recheck(_ row: Setting, option: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = try? self.engine.inspectRow(row, option: option, using: CommandRunner())
            DispatchQueue.main.async {
                guard let result, self.choices[row.id] == option else { return }
                self.preferenceResults[row.id] = result; self.state()
            }
        }
    }
    /// Its own runner, so it never collides with a running job's process or its Stop button.
    func checkPermissions() {
        let target = shellURL
        DispatchQueue.global(qos: .userInitiated).async {
            let list = try? self.engine.permissions(shell: target, runner: CommandRunner())
            DispatchQueue.main.async {
                guard let list else { return }
                self.permissions = list; self.permissionsCheckedAt = Date().timeIntervalSince1970; self.state()
            }
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
        // Prints a bundled script with its includes expanded, to try an edit: ArfanReset1 --script install-go.sh | bash
        if let index = CommandLine.arguments.firstIndex(of: "--script"), index + 1 < CommandLine.arguments.count {
            do { print(try Scripts.load(CommandLine.arguments[index + 1], root: Bundle.main.resourceURL!.appendingPathComponent("Scripts"))) }
            catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
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
