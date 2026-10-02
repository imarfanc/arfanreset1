import Foundation

enum SelfTests {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw SetupError.message(message) }
    }
    static func run() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("arfanreset1-tests-" + UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let runner = CommandRunner()
        let engine = try SetupEngine(resources: Bundle.main.resourceURL!, support: temp.appendingPathComponent("support"), runner: runner)
        let frame = SetupWindow.initialFrame(screen: NSRect(x: 0, y: 0, width: 1920, height: 1440))
        try require(frame.width == 1200 && frame.height == 860 && frame.minX == 100 && 1440 - frame.maxY == 80, "1200×860 window at top-left 100,80")
        try require(engine.settings.count == 86 && Set(engine.settings.map(\.id)).count == 86, "Catalog count and unique IDs")
        try require(engine.installers.count == 12 && engine.guides.count == 10, "Installer and guide coverage")
        for guide in engine.guides {
            let html = try String(contentsOf: engine.resources.appendingPathComponent("Web/guides/" + guide.file), encoding: .utf8)
            try require(!html.contains("data-src=") && !html.contains("type=\"module\"") && !html.contains("src=\"https:"), "Guide is self-contained: " + guide.file)
        }
        for setting in engine.settings {
            try require(["bool", "int", "float", "string", "intDict"].contains(setting.type), "Known setting type")
            try require(try setting.arguments("write").contains(setting.domain), "Fixed defaults argument list")
        }
        let bool = engine.settings.first { $0.type == "bool" && $0.value == "false" }!
        try require(bool.matches("0") && bool.matches("false") && !bool.matches("garbage") && !bool.matches(nil), "Boolean false must not match unknown values")
        let number = engine.settings.first { $0.type == "float" }!
        try require(number.matches(String(Double(number.value)!)), "Numeric normalization")
        let dict = engine.settings.first { $0.type == "intDict" }!
        try require(dict.matches("{\n    0 = 0;\n    1 = 1;\n    2 = 0;\n    3 = 0;\n}"), "Typed dictionary read-back")
        let original = "# custom setup\nexport MY_PROJECT=kept\ncompinit\nsource \"$NVM_DIR/nvm.sh\"\n"
        let updated = try ShellSetup.updated(original, config: engine.shell)
        try require(updated.contains("export MY_PROJECT=kept") && updated.contains("# reset1 deferred: compinit"), "Preserve unrelated Zsh lines")
        try require(try ShellSetup.updated(updated, config: engine.shell) == updated, "Zsh setup must be idempotent")
        for bad in [engine.shell.START, engine.shell.END + "\n" + engine.shell.START, engine.shell.START + engine.shell.START + engine.shell.END + engine.shell.END] {
            do { _ = try ShellSetup.updated(bad, config: engine.shell); throw SetupError.message("Malformed markers were accepted") }
            catch SetupError.message(let message) { try require(message.contains("markers"), "Reject malformed shell markers") }
        }
        let rc = temp.appendingPathComponent(".zshrc")
        try original.write(to: rc, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: rc.path)
        _ = try ShellSetup.install(at: rc, config: engine.shell, runner: runner)
        try require(try String(contentsOf: rc, encoding: .utf8) == updated, "Install proposed Zsh file")
        let backups = temp.appendingPathComponent("backups")
        let first = try fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        try require(first.count == 1 && (try String(contentsOf: first[0], encoding: .utf8)) == original, "Exact Zsh backup")
        _ = try ShellSetup.install(at: rc, config: engine.shell, runner: runner)
        try require(try fm.contentsOfDirectory(atPath: backups.path).count == 1, "No redundant Zsh backup")
        try require((try fm.attributesOfItem(atPath: rc.path)[.posixPermissions] as? NSNumber)?.intValue == 0o640, "Preserve permissions")
        let linked = temp.appendingPathComponent("linked.zshrc")
        try fm.createSymbolicLink(at: linked, withDestinationURL: rc)
        _ = try ShellSetup.install(at: linked, config: engine.shell, runner: runner)
        try require(try fm.destinationOfSymbolicLink(atPath: linked.path) == rc.path, "Preserve Zsh symlink")
        let invalid = temp.appendingPathComponent("invalid.zshrc")
        try "if then\n".write(to: invalid, atomically: true, encoding: .utf8)
        do { _ = try ShellSetup.install(at: invalid, config: engine.shell, runner: runner); throw SetupError.message("Invalid syntax accepted") }
        catch SetupError.message(let message) { try require(message.contains("syntax"), "Reject invalid Zsh") }
        try require(try String(contentsOf: invalid, encoding: .utf8) == "if then\n", "Do not replace invalid original")

        // Simulated defaults backend: never write personal preferences in tests.
        var domain: [String: Any] = [bool.key: true]
        var writes = 0
        runner.testExecutor = { executable, args in
            try require(executable == "/usr/bin/defaults", "Preferences use a fixed executable")
            if args[0] == "export" {
                let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
                return CommandResult(code: 0, output: String(decoding: data, as: UTF8.self))
            }
            if args[0] == "read" {
                return CommandResult(code: domain[args[2]] == nil ? 1 : 0, output: (domain[args[2]] as? Bool).map { $0 ? "1" : "0" } ?? "")
            }
            writes += 1; domain[args[2]] = args.last == "true"
            return CommandResult(code: 0, output: "")
        }
        _ = try engine.check([bool]); try require(writes == 0, "Check must be read only")
        let result = try engine.apply([bool]); try require(result.contains("0 failed") && writes == 1, "Apply verifies writes")
        let backup = try JSONDecoder().decode(PreferenceBackup.self, from: Data(contentsOf: engine.backupURL))
        let previous = try PropertyListSerialization.propertyList(from: backup.entries[0].previous!, format: nil) as! [String: Any]
        try require(previous["value"] as? Bool == true, "Backup preserves original typed value")
        let absent = engine.settings.first { $0.type == "bool" && $0.value == "true" && $0.domain == bool.domain }!
        _ = try engine.apply([bool, absent])
        let second = try JSONDecoder().decode(PreferenceBackup.self, from: Data(contentsOf: engine.backupURL))
        try require(second.entries[1].previous == nil, "Backup distinguishes an absent preference")
        // Restore exactly the previous values, including deletion of an absent key.
        domain[bool.key] = true
        engine.testPreferenceWriter = { setting, value in domain[setting.key] = value; return true }
        let restored = try engine.restore()
        try require(restored.contains("✓ Restored") && !restored.contains("✕"), "Restore verifies its result")
        try require(domain[bool.key] as? Bool == false && domain[absent.key] == nil, "Restore existing typed value and remove previously absent key")
        runner.testExecutor = { _, args in
            if args[0] == "export" { return CommandResult(code: 1, output: "Permission denied") }
            writes += 1; return CommandResult(code: 0, output: "")
        }
        let before = writes
        do { _ = try engine.apply([bool]); throw SetupError.message("Failed backup accepted") }
        catch SetupError.message(let message) { try require(message.contains("back up"), "Fail closed when backup fails") }
        try require(writes == before, "Failed backup prevents all writes")
        runner.testExecutor = nil
        var launchFailed = false
        do { _ = try runner.run("/not/a/real/executable", []) } catch { launchFailed = true }
        try require(launchFailed, "Missing executable must fail")
        let recovered = try runner.run("/usr/bin/true", [])
        try require(recovered.code == 0, "Runner recovers after launch error")
        let timed = try runner.run("/bin/sleep", ["3"], timeout: 0.05)
        try require(timed.code != 0, "Runner enforces timeout")
        runner.cancel()
        do { _ = try runner.run("/usr/bin/true", []); throw SetupError.message("Cancelled action accepted") }
        catch SetupError.message(let message) { try require(message.contains("Stopped"), "Cancellation prevents next process") }
        runner.reset()
        // Disk usage: a real read-only `du` over a fixture, plus the path guard and error counting.
        let tree = temp.appendingPathComponent("disk-home").standardizedFileURL
        try fm.createDirectory(at: tree.appendingPathComponent("big"), withIntermediateDirectories: true)
        try Data(count: 300_000).write(to: tree.appendingPathComponent("big/a.bin"))
        try Data(count: 20_000).write(to: tree.appendingPathComponent("small.txt"))
        try fm.createSymbolicLink(at: tree.appendingPathComponent("link"), withDestinationURL: tree.appendingPathComponent("big"))
        let measured = try runner.run("/usr/bin/du", ["-k", "-x", "-d", "1", tree.path])
        let parsed = DiskUsage.parse(measured.output, root: tree.path)
        let listed = DiskUsage.entries(root: tree.path, sizes: parsed.sizes)
        try require(listed.first?.name == "big" && listed.first?.isDirectory == true, "Largest folder sorts first")
        try require(listed.first(where: { $0.name == "link" })?.isDirectory == false, "Symlinks are not followed or drilled into")
        try require(listed.first(where: { $0.name == "small.txt" })?.bytes ?? 0 >= 20_000 && parsed.total >= 320_000, "Files and total are reported")
        let sample = DiskUsage.parse("du: /r/locked: Operation not permitted\n8\t/r/a\n4\t/r", root: "/r")
        try require(sample.unreadable == 1 && sample.total == 4096 && sample.sizes == ["/r/a": 8192], "Unreadable items are counted, not parsed as sizes")
        try require(DiskUsage.isAllowed(tree.path + "/big", home: tree.path) && DiskUsage.isAllowed(tree.path, home: tree.path), "Home and its contents are allowed")
        try require(!DiskUsage.isAllowed("/etc") && !DiskUsage.isAllowed(DiskUsage.home + "/../etc") && !DiskUsage.isAllowed("-d") && !DiskUsage.isAllowed(DiskUsage.home + "/does-not-exist-" + UUID().uuidString), "Paths outside home or missing are refused")
        let scanned = DiskUsage.scan(path: tree.path, parsed: parsed)
        try require(scanned.bytes >= 320_000 && scanned.parent != nil && scanned.volumeTotal > 0, "Scan carries totals, parent and volume capacity")
        var cache = DiskCache()
        let cacheFile = temp.appendingPathComponent("support/disk-cache.json")
        cache.store(scanned)
        try cache.save(to: cacheFile)
        try require(DiskCache(url: cacheFile, home: tree.path).scans[tree.path]?.bytes == scanned.bytes && DiskCache(url: cacheFile).scans.isEmpty, "Saved scans survive a relaunch; folders outside home are dropped")
        try require((try fm.attributesOfItem(atPath: cacheFile.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Scan cache is private to the user")
        try require(DiskCache(url: temp.appendingPathComponent("missing.json")).scans.isEmpty, "A missing cache starts empty")
        print("Catalog, typed preferences, read-only checks, backup-before-write, shell preservation/idempotence/syntax/symlinks, process recovery/timeout/cancellation, disk usage parsing and path guard passed.")
    }
}
