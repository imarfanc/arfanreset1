import Foundation

enum FunctionTests {
    static func run(resources: URL, temp: URL) throws {
        let fm = FileManager.default
        let functions = try ShellFunctions.load(resources: resources)
        try SelfTests.require(functions.map(\.id) == ["killport", "repos"], "Initial function catalog order")
        let killport = functions[0], repos = functions[1]
        try SelfTests.require(killport.code.contains(#"PORT="$1" uv run --with rich --quiet ~/developer/github/t1/scripts/killport1.py"#), "Preserve supplied killport command")
        try SelfTests.require(repos.code.contains(#"uv run --with rich --quiet ~/developer/github/t1/scripts/repos.py "$@""#), "Preserve repos argument forwarding")
        let original = "# custom content\nexport KEEP_ME=yes\n# == Shell Completions ==\n# leave this alone\n# -- end --\n"
        try SelfTests.require(try ShellFunctions.updated(original + killport.code, function: killport) == original + killport.code, "Exact existing snippets are already installed without duplicates")
        let once = try ShellFunctions.updated(original, function: killport)
        let both = try ShellFunctions.updated(once, function: repos)
        try SelfTests.require(both.hasPrefix(original) && both.contains(killport.code) && both.contains(repos.code), "Keep unrelated shell content and exact function text")
        try SelfTests.require(try ShellFunctions.updated(both, function: killport) == both, "Function installation is idempotent")
        var changed = killport; changed.code += "# updated catalog note\n"
        let upgraded = try ShellFunctions.updated(both, function: changed)
        try SelfTests.require(upgraded.contains(changed.code) && upgraded.contains(repos.code) && upgraded.hasPrefix(original), "Update only one managed function")
        for existing in ["killport() { echo custom; }\n", "function killport { echo custom; }\n", "function killport() { echo custom; }\n"] {
            do { _ = try ShellFunctions.updated(existing, function: killport); throw SetupError.message("Accepted conflicting function") }
            catch { try SelfTests.require(error.localizedDescription.contains("outside this app"), "Do not override an existing function") }
        }
        for bad in ["# >>> arfanreset1 function killport >>>\n", "# <<< arfanreset1 function killport <<<\n# >>> arfanreset1 function killport >>>\n", once + once] {
            do { _ = try ShellFunctions.updated(bad, function: killport); throw SetupError.message("Accepted broken markers") }
            catch { try SelfTests.require(error.localizedDescription.contains("markers"), "Reject malformed or repeated markers") }
        }
        let folder = temp.appendingPathComponent("functions-home")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let rc = folder.appendingPathComponent("real.zshrc"), link = folder.appendingPathComponent(".zshrc")
        try original.write(to: rc, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: rc.path)
        try fm.createSymbolicLink(at: link, withDestinationURL: rc)
        let runner = CommandRunner()
        let preview = try ShellSetup.previewChange(at: link, original: original, proposed: both, runner: runner)
        try SelfTests.require(preview.changed && preview.diff.contains("+killport()") && (try String(contentsOf: rc, encoding: .utf8)) == original, "Function preview does not edit shell")
        _ = try ShellSetup.write(at: link, original: original, result: both, runner: runner)
        try SelfTests.require(try fm.destinationOfSymbolicLink(atPath: link.path) == rc.path, "Function install preserves symlinks")
        try SelfTests.require((try fm.attributesOfItem(atPath: rc.path)[.posixPermissions] as? NSNumber)?.intValue == 0o640, "Function install preserves permissions")
        let backups = folder.appendingPathComponent("backups")
        let files = try fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        try SelfTests.require(files.count == 1 && (try String(contentsOf: files[0], encoding: .utf8)) == original, "Function install backs up exact original")
        _ = try ShellSetup.write(at: link, original: both, result: try ShellFunctions.updated(both, function: killport), runner: runner)
        try SelfTests.require(try fm.contentsOfDirectory(atPath: backups.path).count == 1, "No backup for unchanged function")
        let statuses = ShellFunctions.status(functions, at: link, home: folder.path)
        try SelfTests.require(statuses.allSatisfy { $0.status == "installed" && !$0.missing.isEmpty }, "Saved definitions and missing dependencies are distinct")
        let script = folder.appendingPathComponent("developer/github/t1/scripts/killport1.py")
        try fm.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: script)
        try SelfTests.require(ShellFunctions.status(functions, at: link, home: folder.path)[0].missing.isEmpty, "Dependency file detection uses the requested home")
        do { _ = try ShellSetup.write(at: link, original: both, result: both + "if then\n", runner: runner); throw SetupError.message("Accepted broken syntax") }
        catch { try SelfTests.require(error.localizedDescription.contains("syntax"), "Invalid function content is rejected") }
        try SelfTests.require(try String(contentsOf: rc, encoding: .utf8) == both, "Syntax rejection preserves existing definitions")
        print("Shell function tests: exact text, isolated blocks, conflicts, syntax, backups, idempotence, symlinks and dependency status passed.")
    }
}
