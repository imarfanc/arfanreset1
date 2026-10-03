import Foundation

struct PreferenceResult: Codable {
    let id: String
    let current: String?
    let status, detail: String
    let checkedAt: TimeInterval
}
struct ToolResult: Codable {
    let id, status, version: String
    let path: String?
    let detail: String
    let checkedAt: TimeInterval
}
struct ShellPreview: Codable { let path, diff: String; let changed: Bool }

extension ToolResult {
    /// One tool's run-log entry, with the marks and words the page uses for the same result.
    func logEntry(name: String) -> String {
        let mark = status == "installed" ? "✓ Detected" : status == "missing" ? "• Not found" : "✕ Check failed"
        return (["\(mark) · \(name)"] + [version, path ?? "", detail].filter { !$0.isEmpty }.map { "  " + $0 }).joined(separator: "\n")
    }
}

extension SetupEngine {
    func checkTool(_ id: String, home: String = NSHomeDirectory()) throws -> ToolResult {
        guard installers.contains(where: { $0.id == id }) else { throw SetupError.message("Unknown tool") }
        func result(_ status: String, _ version: String = "", _ path: String? = nil, _ detail: String = "") -> ToolResult {
            ToolResult(id: id, status: status, version: version, path: path, detail: detail, checkedAt: Date().timeIntervalSince1970)
        }
        if id == "chrome" {
            for folder in ["/Applications", home + "/Applications"] {
                let appPath = folder + "/Google Chrome.app"
                let version = try runner.run("/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleShortVersionString", appPath + "/Contents/Info.plist"])
                if version.code == 0, !version.output.isEmpty {
                    return result("installed", version.output, appPath, "Found the Chrome app. It was not opened.")
                }
            }
            return result("missing", "", nil, "No Chrome in /Applications or ~/Applications. It may still be installed somewhere else.")
        }
        if id == "nvm" {
            let folder = URL(fileURLWithPath: home).appendingPathComponent(".nvm")
            let script = folder.appendingPathComponent("nvm.sh")
            guard FileManager.default.fileExists(atPath: script.path) else {
                return result("missing", "", nil, "No nvm.sh in ~/.nvm. Install nvm, then check again. A custom NVM_DIR is not checked.")
            }
            let package = (try? Data(contentsOf: folder.appendingPathComponent("package.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let version = package?["version"] as? String
            return result("installed", version.map { "nvm " + $0 } ?? "Version unavailable", script.path, "Found the nvm files. This does not show that your shell loads nvm.")
        }
        if id == "clt" {
            let found = try runner.run("/usr/bin/xcode-select", ["-p"])
            guard found.code == 0 else { return result("missing", "", nil, "No active developer tools. Run the installer, then check again.") }
            let version = try runner.run("/usr/bin/xcrun", ["clang", "--version"], timeout: 8)
            return result(version.code == 0 ? "installed" : "failed", version.output.components(separatedBy: "\n").first ?? "", found.output, version.code == 0 ? "Active developer tools respond." : "Developer path exists, but clang did not respond.")
        }
        let names = ["install": "brew", "go-install": "go", "zig-install": "zig", "rust-install": "rustc"]
        let name = names[id] ?? id
        let found = try runner.run("/bin/zsh", ["-f", "-c", "command -v " + name])
        var path = found.code == 0 && found.output.hasPrefix("/") ? found.output : nil
        var detail = ""
        if id == "node", path == nil {
            let folder = URL(fileURLWithPath: home).appendingPathComponent(".nvm/versions/node")
            let versions = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            path = versions.map { folder.appendingPathComponent($0 + "/bin/node").path }.first { FileManager.default.isExecutableFile(atPath: $0) }
            if path != nil { detail = "Found the newest Node in ~/.nvm. This does not show which Node your shell uses by default." }
        }
        guard let path else { return result("missing", "", nil, "Not in the standard install paths. It may still be installed somewhere else.") }
        let version = try runner.run(path, name == "go" || name == "zig" ? ["version"] : ["--version"], timeout: 8)
        return result(version.code == 0 ? "installed" : "failed", version.output.components(separatedBy: "\n").prefix(2).joined(separator: " · "), path, version.code == 0 ? detail : "Found it, but its version check failed. Check the path above, or run the installer again.")
    }
}

extension ShellSetup {
    static func preview(at target: URL, config: ShellConfig, runner: CommandRunner) throws -> ShellPreview {
        let original = FileManager.default.fileExists(atPath: target.path) ? try String(contentsOf: target, encoding: .utf8) : ""
        let proposed = try updated(original, config: config)
        return try previewChange(at: target, original: original, proposed: proposed, runner: runner)
    }
    static func previewChange(at target: URL, original: String, proposed: String, runner: CommandRunner) throws -> ShellPreview {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("reset1-preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let before = folder.appendingPathComponent("before.zshrc"), after = folder.appendingPathComponent("after.zshrc")
        try original.write(to: before, atomically: true, encoding: .utf8)
        try proposed.write(to: after, atomically: true, encoding: .utf8)
        let syntax = try runner.run("/bin/zsh", ["-n", after.path])
        guard syntax.code == 0 else { throw SetupError.message("Proposed Zsh configuration has a syntax error. Nothing changed.\n" + syntax.output) }
        let diff = try runner.run("/usr/bin/diff", ["-u", "-L", "Current .zshrc", "-L", "Proposed .zshrc", before.path, after.path])
        guard diff.code == 0 || diff.code == 1 else { throw SetupError.message("Could not create preview: " + diff.output) }
        return ShellPreview(path: target.path, diff: diff.output, changed: original != proposed)
    }
    /// Picker input is accepted only for real backup files beside this selected shell file.
    static func restore(at requested: URL, from backup: URL, runner: CommandRunner) throws -> String {
        let fm = FileManager.default
        let folder = requested.deletingLastPathComponent().appendingPathComponent("backups").resolvingSymlinksInPath()
        let source = backup.resolvingSymlinksInPath()
        let values = try backup.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard source.deletingLastPathComponent() == folder, source.lastPathComponent.hasPrefix(".zshrc.backup-"), values.isSymbolicLink != true, values.isRegularFile == true else {
            throw SetupError.message("Choose a .zshrc.backup- file from this shell folder’s backups directory.")
        }
        let target = requested.resolvingSymlinksInPath()
        let exists = fm.fileExists(atPath: target.path)
        let original = exists ? try Data(contentsOf: target) : nil
        let data = try Data(contentsOf: source)
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".reset1-restore-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        let syntax = try runner.run("/bin/zsh", ["-n", temporary.path])
        guard syntax.code == 0 else { throw SetupError.message("Backup has a Zsh syntax error. Current file preserved.\n" + syntax.output) }
        if data == original { return "This backup already matches \(requested.path). Nothing changed." }
        var saved = ""
        var mode = 0o600
        if exists {
            mode = (try fm.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue ?? mode
            let safety = folder.appendingPathComponent(".zshrc.backup-before-restore-" + UUID().uuidString)
            try fm.copyItem(at: target, to: safety)
            saved = "Current file backed up: \(safety.path)\n"
            guard try Data(contentsOf: target) == original else { throw SetupError.message(".zshrc changed during restore. Nothing replaced; retry after your editor has saved.") }
        } else if fm.fileExists(atPath: target.path) { throw SetupError.message(".zshrc was created during restore. Retry after checking it.") }
        try runner.checkCancellation()
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: temporary.path)
        guard rename(temporary.path, target.path) == 0 else { throw SetupError.message("Could not replace .zshrc. Current file preserved.") }
        return saved + "Restored: \(requested.path)\nFrom: \(source.path)\nOpen a new Terminal to use the restored configuration."
    }
}
