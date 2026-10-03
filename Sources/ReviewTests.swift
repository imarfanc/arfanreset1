import Foundation

enum ReviewTests {
    static func run(resources: URL, temp: URL) throws {
        let require = SelfTests.require
        let fm = FileManager.default
        let runner = CommandRunner()
        let engine = try SetupEngine(resources: resources, support: temp.appendingPathComponent("review-support"), runner: runner)
        let setting = engine.settings.first { $0.type == "bool" && $0.value == "false" }!
        runner.testExecutor = { _, _ in CommandResult(code: 1, output: "Permission denied") }
        try require(try engine.inspect(setting).status == "failed", "Unreadable preferences are failures, not unset values")
        runner.testExecutor = { _, _ in CommandResult(code: 1, output: "The domain/default pair does not exist") }
        let unset = try engine.inspect(setting)
        try require(unset.status == "change" && unset.current == nil, "Absent preference is a proposed change")
        var domain: [String: Any] = [setting.key: true]
        var log = ""
        var results: [PreferenceResult] = []
        engine.progress = { log = $0 }
        engine.preferenceResult = { results.append($0) }
        var wrote = false
        runner.testExecutor = { _, args in
            if args.first == "export" {
                let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
                return CommandResult(code: 0, output: String(decoding: data, as: UTF8.self))
            }
            if args.first == "write" { domain[setting.key] = false; wrote = true; return CommandResult(code: 0, output: "") }
            if wrote { throw SetupError.message("Simulated interruption during read-back") }
            return CommandResult(code: 0, output: "1")
        }
        do { _ = try engine.apply([setting]); throw SetupError.message("Expected interruption") }
        catch { try require(error.localizedDescription.contains("Simulated interruption"), "Stop after simulated write") }
        try require(log.contains("Backup:") && log.contains("Writing:") && log.contains(setting.description), "Interrupted write retains backup and uncertain item")
        try require(fm.fileExists(atPath: engine.backupURL.path) && domain[setting.key] as? Bool == false, "Backup exists after partial change")
        try require(results.isEmpty, "Interrupted read-back never reports success")
        runner.testExecutor = { _, args in
            if args.first == "export" {
                let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
                return CommandResult(code: 0, output: String(decoding: data, as: UTF8.self))
            }
            return CommandResult(code: 0, output: "0")
        }
        _ = try engine.apply([setting])
        try require(results.last?.status == "set" && log.contains("Already set"), "Already-set results reach progress and UI callbacks")
        // Every installer id maps to a check, without invoking a real installed program.
        runner.testExecutor = { executable, args in
            if executable == "/usr/bin/xcode-select" { return CommandResult(code: 0, output: "/fixture/Developer") }
            if executable == "/bin/zsh" { return CommandResult(code: 0, output: "/fixture/" + args.last!.components(separatedBy: " ").last!) }
            return CommandResult(code: 0, output: "fixture version 1.2.3")
        }
        let toolHome = temp.appendingPathComponent("tool-home")
        let nvmFolder = toolHome.appendingPathComponent(".nvm")
        try fm.createDirectory(at: nvmFolder, withIntermediateDirectories: true)
        try "# fixture".write(to: nvmFolder.appendingPathComponent("nvm.sh"), atomically: true, encoding: .utf8)
        try Data(#"{"version":"1.2.3"}"#.utf8).write(to: nvmFolder.appendingPathComponent("package.json"))
        for installer in engine.installers {
            let result = try engine.checkTool(installer.id, home: toolHome.path)
            try require(result.id == installer.id && result.status == "installed" && result.path != nil && result.version.contains("1.2.3"), "Installer check maps to version and path: " + installer.id)
        }
        try require(try engine.checkTool("nvm", home: temp.appendingPathComponent("no-nvm").path).status == "missing", "Missing nvm has its own result")
        let node = engine.installers.first { $0.id == "node" }!
        let nvm = engine.installers.first { $0.id == "nvm" }!
        try require(node.command.contains("nvm install 26") && !node.command.contains("nvm.sh") && !nvm.command.contains("nvm install"), "Node and nvm install separately without explicit sourcing")
        for installer in engine.installers where !installer.optional && !["clt", "install"].contains(installer.id) {
            try require(installer.website?.hasPrefix("https://") == true && installer.docs?.hasPrefix("https://") == true, "CLI cards have website and docs links")
        }
        try require(!engine.guides.contains { ["install-cli-tools.html", "optional-cli-tools.html"].contains($0.file) }, "Removed CLI guides stay out of catalog")
        runner.testExecutor = { _, _ in CommandResult(code: 1, output: "") }
        try require(try engine.checkTool("deno").status == "missing", "Missing tool stays unverified")
        runner.testExecutor = { executable, _ in CommandResult(code: executable == "/bin/zsh" ? 0 : 1, output: executable == "/bin/zsh" ? "/fixture/deno" : "Cannot execute") }
        try require(try engine.checkTool("deno").status == "failed", "Failed version check is not installed")
        runner.testExecutor = nil
        let folder = temp.appendingPathComponent("review-shell")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("actual.zshrc"), link = folder.appendingPathComponent(".zshrc")
        let original = "export KEEP_ME=yes\n"
        try original.write(to: target, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        let preview = try ShellSetup.preview(at: link, config: engine.shell, runner: runner)
        try require(preview.changed && preview.diff.contains("+++ Proposed .zshrc") && preview.diff.contains("+" + engine.shell.START), "Preview is a focused unified diff")
        try require(try String(contentsOf: target, encoding: .utf8) == original && !fm.fileExists(atPath: folder.appendingPathComponent("backups").path), "Preview writes neither shell file nor backups")
        _ = try ShellSetup.install(at: link, config: engine.shell, runner: runner)
        let backupFolder = folder.appendingPathComponent("backups")
        let backup = try fm.contentsOfDirectory(at: backupFolder, includingPropertiesForKeys: nil)[0]
        let restored = try ShellSetup.restore(at: link, from: backup, runner: runner)
        try require(restored.contains("Current file backed up:") && (try String(contentsOf: target, encoding: .utf8)) == original, "Restore creates safety backup and restores original")
        try require(try fm.destinationOfSymbolicLink(atPath: link.path) == target.path, "Restore preserves symlink")
        try require((try fm.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue == 0o640, "Restore preserves current permissions")
        let broken = backupFolder.appendingPathComponent(".zshrc.backup-broken")
        try "if then\n".write(to: broken, atomically: true, encoding: .utf8)
        do { _ = try ShellSetup.restore(at: link, from: broken, runner: runner); throw SetupError.message("Accepted bad backup") }
        catch { try require(error.localizedDescription.contains("syntax"), "Reject invalid backup syntax") }
        do { _ = try ShellSetup.restore(at: link, from: target, runner: runner); throw SetupError.message("Accepted arbitrary file") }
        catch { try require(error.localizedDescription.contains("Choose a .zshrc.backup-"), "Restore only accepts this shell folder's backups") }
        try require(try String(contentsOf: target, encoding: .utf8) == original, "Rejected restores preserve current shell")
        let another = backupFolder.appendingPathComponent(".zshrc.backup-another")
        try "export RESTORED=yes\n".write(to: another, atomically: true, encoding: .utf8)
        runner.cancel()
        do { _ = try ShellSetup.restore(at: link, from: another, runner: runner); throw SetupError.message("Ignored cancellation") }
        catch { try require(error.localizedDescription.contains("Stopped"), "Cancellation stops restore") }
        try require(try String(contentsOf: target, encoding: .utf8) == original, "Cancelled restore preserves file")
        print("Review tests: preference statuses, interrupted progress, all installer mappings, Zsh diff and guarded restore passed.")
    }
}
