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
        // 86 imported rows, one of them replaced by the Appearance choice, plus the Icon & widget style choice.
        try require(engine.settings.count == 87 && Set(engine.settings.map(\.id)).count == 87, "Catalog count and unique IDs")
        try require(engine.installers.count == 15 && engine.guides.count == 5, "Installer and guide coverage")
        for item in AccessibilityAction.all {
            let url = AccessibilityAction.codexURL(for: item)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            try require(url.scheme == "codex" && url.host == "new" && query?.count == 1 && query?.first?.value == item.prompt, "Codex draft URL preserves the full prompt without an auto-send or model parameter")
            let script = engine.scripts[item.scriptName] ?? ""
            try require(script.contains("if my switchValue(targetSwitch) is 1 then return") && script.components(separatedBy: "to click targetSwitch").count == 2, "Enable scripts guard already-on state and contain one click")
            try require(script.contains("AX_ID=") && script.contains("/usr/bin/osascript"), "Accessibility script is bundled and expanded")
            let cliFile = temp.appendingPathComponent("cli-\(item.id).sh")
            let fixtureScript = "printf '%s' '$HOME $(echo must-not-run)'"
            let mock = "codex() { if [ \"$1\" = login ]; then return 0; fi; printf '%s\\n' \"$@\"; /bin/cat \"$8/enable-setting.sh\"; }\nTMPDIR='\(temp.path)'\n"
            try (mock + item.cliCommand(script: fixtureScript)).write(to: cliFile, atomically: true, encoding: .utf8)
            let cliResult = try runner.run("/bin/bash", [cliFile.path])
            try require(cliResult.code == 0 && cliResult.output.contains("--model\ngpt-6-luna\n--sandbox\nworkspace-write\n--ask-for-approval\non-request") && cliResult.output.contains(fixtureScript), "CLI wrapper passes model and approval flags and preserves script literally using a mock, without running Codex or AppleScript")
        }
        let clt = engine.installers.first { $0.id == "clt" }
        try require(clt?.script == "install-clt.zsh" && clt?.command.hasPrefix("zsh <<'ZSH'\n") == true && clt?.command.hasSuffix("\nZSH") == true, "CLT runs its script file in a zsh heredoc")
        try require(clt?.command.contains("softwareupdate -i") == true && clt?.command.contains("heading() {") == true, "CLT script carries the shared style inline")
        // Scripts: every include expanded, every shell script valid once expanded, every guide reference present.
        for (name, body) in engine.scripts {
            try require(!body.contains("# @include") && !body.hasPrefix("#!"), "Script is expanded and has no shebang: " + name)
            guard name.hasSuffix(".sh") || name.hasSuffix(".zsh") else { continue }
            try require(!body.components(separatedBy: "\n").contains(Scripts.runner(name).close), "Heredoc closer is not a script line: " + name)
            let file = temp.appendingPathComponent(name)
            try body.write(to: file, atomically: true, encoding: .utf8)
            let syntax = try runner.run(name.hasSuffix(".zsh") ? "/bin/zsh" : "/bin/bash", ["-n", file.path])
            try require(syntax.code == 0, "Expanded script syntax: \(name) \(syntax.output)")
        }
        try require(engine.scripts["mission-control-off.py"]?.contains("def make_table(") == true, "Python scripts carry the shared style inline")
        for bad in ["../Config/settings.json", "lib/style.sh", "x.rb", ""] { try require(!Scripts.isValidName(bad), "Reject script name: " + bad) }
        let fixtureScripts = temp.appendingPathComponent("scripts")
        try fm.createDirectory(at: fixtureScripts.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try "say() { print hi; }\n".write(to: fixtureScripts.appendingPathComponent("lib/a.sh"), atomically: true, encoding: .utf8)
        try "#!/bin/zsh\n# @include lib/a.sh\nsay\n".write(to: fixtureScripts.appendingPathComponent("ok.zsh"), atomically: true, encoding: .utf8)
        try "# @include ../secret.sh\n".write(to: fixtureScripts.appendingPathComponent("bad.sh"), atomically: true, encoding: .utf8)
        try require(try Scripts.load("ok.zsh", root: fixtureScripts) == "say() { print hi; }\nsay", "Include expands in place and the shebang goes")
        do { _ = try Scripts.load("bad.sh", root: fixtureScripts); throw SetupError.message("Include outside lib accepted") }
        catch SetupError.message(let message) { try require(message.contains("bad include"), "Includes stay inside lib") }
        for guide in engine.guides {
            let html = try String(contentsOf: engine.resources.appendingPathComponent("Web/guides/" + guide.file), encoding: .utf8)
            try require(!html.contains("type=\"module\"") && !html.contains("src=\"https:"), "Guide is self-contained: " + guide.file)
            let regex = try NSRegularExpression(pattern: #"data-src="([^"]+)""#)
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                let name = String(html[Range(match.range(at: 1), in: html)!])
                try require(engine.scripts[name] != nil, "Guide script exists: \(guide.file) → \(name)")
            }
        }
        for row in engine.settings {
            // A choice row is checked through every key of every option it offers.
            for setting in row.options.map({ options in options.flatMap { row.components(option: $0.id) } }) ?? [row] {
                try require(["bool", "int", "float", "string", "intDict", "delete"].contains(setting.type), "Known setting type")
                try require(try setting.arguments("write").contains(setting.domain), "Fixed defaults argument list")
            }
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
        let shown = ShellSetup.files(for: rc)
        try require(shown.map(\.id) == ["zshrc", "backups", "zcompdump"] && shown[0].exists && shown[1].isFolder && shown[1].items == 1 && !shown[2].exists, "Shell files list the .zshrc, its backups and the completion cache")
        try require(ShellSetup.files(for: linked).map(\.id) == ["zshrc", "target", "backups", "zcompdump"], "A symlinked .zshrc also lists its target")
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
        try require(scanned.folders?.count == 1 && scanned.files?.count == 2 && scanned.itemCount == 3 && scanned.folders!.bytes + scanned.files!.bytes <= scanned.bytes, "Folders and files are counted apart")
        // A scan saved before the split view has no kinds; it must still load and count its items.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(scanned)) as! [String: Any]
        legacy["folders"] = nil; legacy["files"] = nil
        let old = try JSONDecoder().decode(DiskScan.self, from: JSONSerialization.data(withJSONObject: legacy))
        try require(old.folders == nil && old.itemCount == old.entries.count + old.moreCount, "Older saved scans still load")
        var cache = DiskCache()
        let cacheFile = temp.appendingPathComponent("support/disk-cache.json")
        cache.store(scanned)
        try cache.save(to: cacheFile)
        try require(DiskCache(url: cacheFile, home: tree.path).scans[tree.path]?.bytes == scanned.bytes && DiskCache(url: cacheFile).scans.isEmpty, "Saved scans survive a relaunch; folders outside home are dropped")
        try require((try fm.attributesOfItem(atPath: cacheFile.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Scan cache is private to the user")
        try require(DiskCache(url: temp.appendingPathComponent("missing.json")).scans.isEmpty, "A missing cache starts empty")
        // Permissions: read only, against a fixture home and fixture shell folders.
        let fakeHome = temp.appendingPathComponent("perm-home")
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        try require(Permissions.fullDiskAccess(home: fakeHome.path) == nil, "No probe files means Full Disk Access is unknown")
        try fm.createDirectory(at: fakeHome.appendingPathComponent("Library/Safari"), withIntermediateDirectories: true)
        try require(Permissions.fullDiskAccess(home: fakeHome.path) == true, "A readable probe means access")
        let open = try engine.permissions(shell: rc, runner: runner, home: fakeHome.path)
        try require(open.map(\.id) == ["fda", "admin", "terminal", "zsh", "support"], "Every permission is reported in order")
        try require(open.first { $0.id == "zsh" }?.status == "granted" && open.first { $0.id == "support" }?.status == "granted", "Writable fixture folders are granted")
        let locked = temp.appendingPathComponent("locked")
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let closed = try engine.permissions(shell: locked.appendingPathComponent(".zshrc"), runner: runner, home: fakeHome.path)
        try require(closed.first { $0.id == "zsh" }?.status == "missing", "A read-only shell folder is reported")
        try require(Permissions.writable(locked.path + "/not/yet") == false && Permissions.writable(temp.path + "/not/yet"), "Missing folders inherit their parent's writability")
        try require(!fm.fileExists(atPath: locked.appendingPathComponent(".zshrc").path) && !fm.fileExists(atPath: temp.appendingPathComponent("not").path), "Permission checks create nothing")
        try FunctionTests.run(resources: Bundle.main.resourceURL!, temp: temp)
        try ChoiceTests.run(resources: Bundle.main.resourceURL!, temp: temp)
        try ReviewTests.run(resources: Bundle.main.resourceURL!, temp: temp)
        print("Catalog, typed preferences, read-only checks, backup-before-write, shell preservation/idempotence/syntax/symlinks, process recovery/timeout/cancellation, disk usage parsing, split counts and path guard, permission checks, script expansion and syntax passed.")
    }
}
