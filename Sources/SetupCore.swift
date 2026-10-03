import Foundation
import CoreFoundation

struct Setting: Codable {
    let id, section, group, domain, key, type, value, description: String
    var currentHost: Bool? = nil
    /// A choice row offers these instead of one fixed value: `type` is "choice" and `value` names the default option.
    var options: [Option]? = nil
    /// One line shown under the row, such as when the change takes effect.
    var note: String? = nil
    struct Option: Codable { let id, label: String; let writes: [Write] }
    /// One key an option sets. Type "delete" removes the key, which is how macOS stores some of its defaults.
    struct Write: Codable { let key, type, value: String }
    var protected: Bool { domain == "com.apple.universalaccess" }
    var resolvedValue: String { value.replacingOccurrences(of: "~/", with: NSHomeDirectory() + "/") }
    var scope: [String] { currentHost == true ? ["-currentHost"] : [] }
    func arguments(_ verb: String) throws -> [String] {
        if verb == "write", type == "delete" { return scope + ["delete", domain, key] }
        var result = scope + [verb, domain, key]
        if verb == "write" {
            if type == "intDict" {
                let dict = try JSONDecoder().decode([String: Int].self, from: Data(value.utf8))
                result += ["-dict"] + dict.keys.sorted().flatMap { [$0, "-int", String(dict[$0]!)] }
            } else { result += ["-" + type, resolvedValue] }
        }
        return result
    }
    func matches(_ actual: String?) -> Bool {
        if type == "delete" { return actual == nil }
        guard let actual else { return false }
        switch type {
        case "bool":
            let truth = ["1", "true", "yes"]
            let falsity = ["0", "false", "no"]
            let lower = actual.lowercased()
            return resolvedValue == "true" ? truth.contains(lower) : falsity.contains(lower)
        case "int", "float": return Double(actual) == Double(resolvedValue)
        case "intDict":
            guard let expected = try? JSONDecoder().decode([String: Int].self, from: Data(value.utf8)),
                  let regex = try? NSRegularExpression(pattern: #"(?m)^\s*"?([^"=\s]+)"?\s*=\s*(-?\d+);$"#) else { return false }
            let ns = actual as NSString
            var found: [String: Int] = [:]
            for match in regex.matches(in: actual, range: NSRange(location: 0, length: ns.length)) {
                found[ns.substring(with: match.range(at: 1))] = Int(ns.substring(with: match.range(at: 2)))
            }
            return found == expected
        default: return actual == resolvedValue
        }
    }
    /// The option a choice row will apply: the one picked on the page, or the row's default.
    func option(_ id: String?) -> Option? { options?.first { $0.id == id } ?? options?.first { $0.id == value } }
    /// The single-key settings a row writes: itself, or one for each key of a choice's option.
    func components(option id: String? = nil) -> [Setting] {
        guard let option = option(id) else { return [self] }
        return option.writes.map { Setting(id: self.id + "." + $0.key, section: section, group: group, domain: domain, key: $0.key, type: $0.type, value: $0.value, description: "\(description): \(option.label) · \($0.key)", currentHost: currentHost) }
    }
}

/// `command` is what Terminal runs and the page shows. A scripted installer's command is its bundled script inside the
/// same heredoc runner the guides use, so a copied command is self-contained too.
struct Installer: Codable { let id, name, command: String; let guide: String?; let optional: Bool; var script: String? = nil; var website: String? = nil; var docs: String? = nil; var note: String? = nil }

/// Editable scripts in Resources/Scripts. A `# @include lib/<file>` line is replaced by that file (one level, no nesting),
/// so every script the guides show or Terminal runs stands alone. The shebang is dropped: a heredoc picks the interpreter.
enum Scripts {
    static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9_-]+\.(sh|zsh|py|ts)$"#, options: .regularExpression) != nil
    }
    static func load(_ name: String, root: URL) throws -> String {
        guard isValidName(name) else { throw SetupError.message("Unknown script name: \(name)") }
        let text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        if lines.first?.hasPrefix("#!") == true { lines.removeFirst() }
        let expanded = try lines.map { line -> String in
            guard line.hasPrefix("# @include ") else { return line }
            let include = String(line.dropFirst("# @include ".count))
            guard include.range(of: #"^lib/[A-Za-z0-9_-]+\.(sh|py)$"#, options: .regularExpression) != nil else { throw SetupError.message("\(name): bad include \(include)") }
            return try String(contentsOf: root.appendingPathComponent(include), encoding: .utf8).trimmingCharacters(in: .newlines)
        }
        return expanded.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
    /// Every top-level script, expanded, by file name.
    static func all(root: URL) throws -> [String: String] {
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path).filter(isValidName)
        return try Dictionary(uniqueKeysWithValues: names.map { ($0, try load($0, root: root)) })
    }
    /// The heredoc a guide shows around a script, by interpreter.
    static func runner(_ name: String) -> (open: String, close: String) {
        name.hasSuffix(".zsh") ? ("zsh <<'ZSH'", "ZSH") : ("bash -e <<'SH'", "SH")
    }
}
/// One macOS permission the app relies on. `status` is "granted", "missing" or "unknown"; `settings` names a System Settings pane.
struct Permission: Codable { let id, name, status, detail, usedBy: String; var settings: String? = nil }
/// `about` is the one line under a guide's title in the Reference guides list.
struct Guide: Codable { let file, title: String; var about: String? = nil }
struct ShellConfig: Decodable { let START, END, CONFIG: String; let EAGER_LINES: [String] }

enum SetupError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct CommandResult { let code: Int32; let output: String }

/// Built-in executables only; no user shell startup files are sourced by the app.
final class CommandRunner {
    var testExecutor: ((String, [String]) throws -> CommandResult)?
    private let lock = NSLock()
    private var active: Process?
    private var cancelled = false
    func checkCancellation() throws {
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped { throw SetupError.message("Stopped by you. Nothing more was changed. Finished items are listed above.") }
    }
    func reset() { lock.lock(); cancelled = false; lock.unlock() }
    func cancel() {
        lock.lock(); cancelled = true; let process = active; lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }
    func run(_ executable: String, _ args: [String], timeout: TimeInterval = 30) throws -> CommandResult {
        if let testExecutor { return try testExecutor(executable, args) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = [NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/.deno/bin", NSHomeDirectory() + "/.bun/bin", NSHomeDirectory() + "/.cargo/bin", NSHomeDirectory() + "/.opencode/bin", NSHomeDirectory() + "/.atuin/bin", "/opt/homebrew/bin", "/usr/local/go/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        process.environment = env
        lock.lock()
        if cancelled { lock.unlock(); throw SetupError.message("Stopped by you. Nothing more was changed. Finished items are listed above.") }
        do { try process.run() } catch { lock.unlock(); throw error }
        active = process
        lock.unlock()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); deadline.cancel()
        lock.lock(); active = nil; let stopped = cancelled; lock.unlock()
        if stopped { throw SetupError.message("Stopped by you. Nothing more was changed. Finished items are listed above.") }
        let output = String(decoding: data.prefix(500_000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandResult(code: process.terminationStatus, output: output)
    }
}

/// A file or folder in the user's shell folder that Zsh setup changes or leads to; shown so it can be inspected.
struct ShellFile: Codable { let id, name, path, change: String; let exists, isFolder: Bool; var items: Int? = nil }

enum ShellSetup {
    /// Read only. `id`s are what the page may ask the app to show or open; paths never come from the page.
    static func files(for requested: URL) -> [ShellFile] {
        let fm = FileManager.default
        let folder = requested.deletingLastPathComponent()
        let target = requested.resolvingSymlinksInPath()
        func file(_ id: String, _ name: String, _ url: URL, _ change: String) -> ShellFile {
            var directory: ObjCBool = false
            let exists = fm.fileExists(atPath: url.path, isDirectory: &directory)
            let items = exists && directory.boolValue ? (try? fm.contentsOfDirectory(atPath: url.path))?.filter { !$0.hasPrefix(".") || $0.hasPrefix(".zshrc") }.count : nil
            return ShellFile(id: id, name: name, path: url.path, change: change, exists: exists, isFolder: directory.boolValue, items: items)
        }
        var list = [file("zshrc", ".zshrc", requested, target.path == requested.path
            ? "Setup rewrites one marked block here and comments out the eager loader lines it recognizes. The file is created if it is missing."
            : "A symlink. It stays a link. Setup updates the file it points to.")]
        if target.path != requested.path {
            list.append(file("target", target.lastPathComponent, target, "The real file behind the link. Setup rewrites one marked block in it and keeps its permissions."))
        }
        list.append(file("backups", "backups", folder.appendingPathComponent("backups"), "Created on the first change. It holds a dated copy of .zshrc from before each change. The app never deletes anything in it."))
        list.append(file("zcompdump", ".zcompdump-reset1", folder.appendingPathComponent(".zcompdump-reset1"), "Not written by the app. zsh creates this completion cache on your first Tab after setup."))
        return list
    }

    static func updated(_ original: String, config: ShellConfig) throws -> String {
        let starts = original.components(separatedBy: config.START).count - 1
        let ends = original.components(separatedBy: config.END).count - 1
        guard starts == ends, starts <= 1 else { throw SetupError.message("Ambiguous reset1 markers. Your .zshrc was not changed.") }
        var text = original
        if let start = text.range(of: config.START), let end = text.range(of: config.END) {
            guard start.lowerBound < end.lowerBound else { throw SetupError.message("Reversed reset1 markers. Your .zshrc was not changed.") }
            var upper = end.upperBound
            if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
            text.removeSubrange(start.lowerBound..<upper)
        }
        let regex = try NSRegularExpression(pattern: #"(?ms)^# == Shell Completions =+[^\n]*\n.*?^# -- end -+[^\n]*(?:\n|$)"#)
        text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        let eager = Set(config.EAGER_LINES)
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let command = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " #")[0].trimmingCharacters(in: .whitespaces)
            return eager.contains(command) ? "# reset1 deferred: " + line.trimmingCharacters(in: .whitespaces) : line
        }
        var prefix = lines.joined(separator: "\n")
        while prefix.hasSuffix("\n") { prefix.removeLast() }
        return (prefix.isEmpty ? "" : prefix + "\n\n") + config.START + "\n" + config.CONFIG.trimmingCharacters(in: .newlines) + "\n" + config.END + "\n"
    }

    static func install(at requested: URL, config: ShellConfig, runner: CommandRunner) throws -> String {
        let fm = FileManager.default
        let rc = requested.resolvingSymlinksInPath()
        let exists = fm.fileExists(atPath: rc.path)
        let original = exists ? try String(contentsOf: rc, encoding: .utf8) : ""
        let result = try updated(original, config: config)
        return try write(at: requested, original: original, result: result, runner: runner)
    }

    /// Shared by Zsh setup and function installation. Never evaluates the proposed shell code.
    static func write(at requested: URL, original: String, result: String, runner: CommandRunner) throws -> String {
        let fm = FileManager.default
        let rc = requested.resolvingSymlinksInPath()
        let exists = fm.fileExists(atPath: rc.path)
        if result == original { return "Already up to date: \(rc.path)" }
        try fm.createDirectory(at: rc.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = rc.deletingLastPathComponent().appendingPathComponent(".arfanreset1-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }
        try result.write(to: temp, atomically: true, encoding: .utf8)
        let check = try runner.run("/bin/zsh", ["-n", temp.path])
        guard check.code == 0 else { throw SetupError.message("Zsh syntax check failed. Original preserved.\n" + check.output) }
        var message = ""
        var mode: Int = 0o600
        if exists {
            // Preserve symlink targets, permissions and unrelated configuration.
            let attributes = try fm.attributesOfItem(atPath: rc.path)
            mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? mode
            let folder = requested.deletingLastPathComponent().appendingPathComponent("backups")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let backup = folder.appendingPathComponent(".zshrc.backup-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6))")
            try fm.copyItem(at: rc, to: backup)
            message = "Backup: \(backup.path)\n"
            guard try String(contentsOf: rc, encoding: .utf8) == original else { throw SetupError.message(".zshrc changed during setup. Retry after your other editor has saved.") }
        }
        try runner.checkCancellation()
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: temp.path)
        // POSIX rename replaces atomically within the same directory and keeps symlinks intact.
        guard rename(temp.path, rc.path) == 0 else { throw SetupError.message("Could not replace .zshrc: \(String(cString: strerror(errno)))") }
        return message + "Updated: \(rc.path)\nOpen a new Terminal to load the updated configuration."
    }
}

struct PreferenceBackup: Codable {
    let date: Date
    let entries: [Entry]
    struct Entry: Codable { let setting: Setting; let previous: Data? }
}

final class SetupEngine {
    let runner: CommandRunner
    let resources: URL
    let support: URL
    let settings: [Setting]
    let installers: [Installer]
    let guides: [Guide]
    let functions: [ShellFunction]
    let shell: ShellConfig
    let scripts: [String: String]
    var progress: ((String) -> Void)?
    var preferenceResult: ((PreferenceResult) -> Void)?
    var toolResult: ((ToolResult) -> Void)?
    var testPreferenceWriter: ((Setting, Any?) -> Bool)?
    var backupURL: URL { support.appendingPathComponent("preferences-latest.json") }
    init(resources: URL, support: URL, runner: CommandRunner = CommandRunner()) throws {
        self.runner = runner
        self.resources = resources; self.support = support
        func load<T: Decodable>(_ name: String) throws -> T {
            try JSONDecoder().decode(T.self, from: Data(contentsOf: resources.appendingPathComponent("Config/" + name)))
        }
        functions = try ShellFunctions.load(resources: resources)
        settings = try Self.merge(try load("settings.json"), choices: try load("choices.json"))
        guides = try load("guides.json"); shell = try load("shell.json")
        let scripts = try Scripts.all(root: resources.appendingPathComponent("Scripts"))
        self.scripts = scripts
        struct Entry: Decodable { let id, name: String; let optional: Bool; let command, script, guide, website, docs, note: String? }
        let entries: [Entry] = try load("installers.json")
        installers = try entries.map { entry in
            if let name = entry.script {
                guard let body = scripts[name], name.hasSuffix(".sh") || name.hasSuffix(".zsh") else { throw SetupError.message("Installer \(entry.id) needs a shell script in Scripts: \(name)") }
                let runner = Scripts.runner(name)
                return Installer(id: entry.id, name: entry.name, command: runner.open + "\n" + body + "\n" + runner.close, guide: entry.guide, optional: entry.optional, script: name, website: entry.website, docs: entry.docs, note: entry.note)
            }
            guard let command = entry.command else { throw SetupError.message("Installer \(entry.id) has no command or script") }
            return Installer(id: entry.id, name: entry.name, command: command, guide: entry.guide, optional: entry.optional, website: entry.website, docs: entry.docs, note: entry.note)
        }
    }
    /// Choice rows live in choices.json, which the importer never rewrites. A choice takes the place of any imported
    /// row that writes one of its keys. Otherwise it goes at the end of its group.
    static func merge(_ imported: [Setting], choices: [Setting]) throws -> [Setting] {
        let types = ["bool", "int", "float", "string", "intDict", "delete"]
        for choice in choices {
            guard let options = choice.options, choice.type == "choice", choice.option(nil) != nil, Set(options.map(\.id)).count == options.count,
                  options.allSatisfy({ !$0.writes.isEmpty && $0.writes.allSatisfy { types.contains($0.type) } }) else { throw SetupError.message("Invalid choice in choices.json: \(choice.id)") }
        }
        func owns(_ choice: Setting, _ setting: Setting) -> Bool {
            choice.domain == setting.domain && choice.options!.contains { $0.writes.contains { $0.key == setting.key } }
        }
        var merged: [Setting] = []
        var placed = Set<String>()
        for setting in imported {
            guard let choice = choices.first(where: { owns($0, setting) }) else { merged.append(setting); continue }
            if placed.insert(choice.id).inserted { merged.append(choice) }
        }
        for choice in choices where !placed.contains(choice.id) {
            if let index = merged.lastIndex(where: { $0.section == choice.section && $0.group == choice.group }) { merged.insert(choice, at: index + 1) } else { merged.append(choice) }
        }
        guard Set(merged.map(\.id)).count == merged.count else { throw SetupError.message("Duplicate preference IDs") }
        return merged
    }
    func read(_ setting: Setting) throws -> String? {
        let result = try runner.run("/usr/bin/defaults", setting.arguments("read"))
        return result.code == 0 ? result.output : nil
    }
    /// What one `defaults read` says about a key. A missing key is a proposed change, unless removing it is the proposal.
    static func missingKey(_ read: CommandResult) -> Bool {
        read.code != 0 && (read.output.contains("does not exist") ||
            (read.output.contains("Error: Could not find key '") && read.output.contains("' in domain '")))
    }
    static func status(_ setting: Setting, _ read: CommandResult) -> String {
        if read.code == 0 { return setting.matches(read.output) ? "set" : "change" }
        return missingKey(read) ? (setting.matches(nil) ? "set" : "change") : "failed"
    }
    func inspect(_ setting: Setting, using other: CommandRunner? = nil) throws -> PreferenceResult {
        let result = try (other ?? runner).run("/usr/bin/defaults", setting.arguments("read"))
        let status = Self.status(setting, result)
        return PreferenceResult(id: setting.id, current: result.code == 0 ? result.output : nil, status: status, detail: status == "failed" ? result.output : "", checkedAt: Date().timeIntervalSince1970)
    }
    /// A row's result. A choice reads each of its keys once: `current` names the option this Mac matches now, and the
    /// status says whether the chosen option is already in place.
    func inspectRow(_ row: Setting, option id: String? = nil, using other: CommandRunner? = nil) throws -> PreferenceResult {
        guard let options = row.options, let chosen = row.option(id) else { return try inspect(row, using: other) }
        var reads: [String: CommandResult] = [:]
        func status(_ component: Setting) throws -> String {
            if reads[component.key] == nil { reads[component.key] = try (other ?? runner).run("/usr/bin/defaults", component.arguments("read")) }
            return Self.status(component, reads[component.key]!)
        }
        let now = try options.first { option in try row.components(option: option.id).allSatisfy { try status($0) == "set" } }
        let parts = try row.components(option: chosen.id).map(status)
        let state = parts.contains("failed") ? "failed" : parts.allSatisfy { $0 == "set" } ? "set" : "change"
        let problems = reads.keys.sorted().compactMap { key in reads[key].flatMap { $0.code != 0 && !Self.missingKey($0) ? $0.output : nil } }
        return PreferenceResult(id: row.id, current: state == "failed" ? nil : now?.label ?? "Something else", status: state, detail: state == "failed" ? problems.joined(separator: " ") : "", checkedAt: Date().timeIntervalSince1970)
    }
    func check(_ rows: [Setting], choices: [String: String] = [:]) throws -> String {
        var lines = ["Read-only check · \(rows.count) preferences", ""]
        for row in rows {
            let result = try inspectRow(row, option: choices[row.id])
            preferenceResult?(result)
            let label = result.status == "set" ? "✓ Already set" : result.status == "failed" ? "✕ Couldn’t read" : "• Would change"
            lines.append("\(label) · \(row.description)\n  \(result.current ?? (result.status == "failed" ? "Unreadable" : "Not set")) → \(row.option(choices[row.id])?.label ?? row.resolvedValue)")
            progress?(lines.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }
    func capture(_ selected: [Setting]) throws -> PreferenceBackup {
        var entries: [PreferenceBackup.Entry] = []
        var domains: [String: [String: Any]] = [:]
        for setting in selected {
            let cacheKey = setting.domain + (setting.currentHost == true ? ":host" : "")
            if domains[cacheKey] == nil {
                let exported = try runner.run("/usr/bin/defaults", setting.scope + ["export", setting.domain, "-"])
                if exported.code == 0 {
                    guard let data = exported.output.data(using: .utf8), let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                        throw SetupError.message("Could not back up \(setting.domain). No settings were changed.")
                    }
                    domains[cacheKey] = dict
                } else {
                    // Only a missing domain is safe to treat as empty.
                    guard exported.output.contains("does not exist") else { throw SetupError.message("Could not back up \(setting.domain): \(exported.output)") }
                    domains[cacheKey] = [:]
                }
            }
            let old = domains[cacheKey]![setting.key]
            let payload = try old.map { try PropertyListSerialization.data(fromPropertyList: ["value": $0], format: .binary, options: 0) }
            entries.append(.init(setting: setting, previous: payload))
        }
        return PreferenceBackup(date: Date(), entries: entries)
    }
    func apply(_ rows: [Setting], choices: [String: String] = [:]) throws -> String {
        guard !rows.isEmpty else { throw SetupError.message("Select at least one preference.") }
        // A choice row becomes the keys its chosen option writes. From here on the work is key by key.
        let parts = rows.flatMap { row in row.components(option: choices[row.id]).map { (row: row, setting: $0) } }
        let selected = parts.map { $0.setting }
        let backup = try capture(selected)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        let archive = support.appendingPathComponent("preferences-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json")
        try data.write(to: archive, options: .atomic)
        try data.write(to: backupURL, options: .atomic)
        var lines = ["Backup: \(archive.path)", ""]
        progress?(lines.joined(separator: "\n"))
        var failed: [String: String] = [:]     // rows with a key that could not be verified, and what defaults said
        for (row, setting) in parts {
            let plain = row.options == nil
            try runner.checkCancellation()
            lines.append("Checking: \(setting.description)")
            progress?(lines.joined(separator: "\n"))
            let before = try inspect(setting)
            if before.status == "set" {
                if plain { preferenceResult?(before) }
                lines.append("✓ Already set · \(setting.description)")
                progress?(lines.joined(separator: "\n")); continue
            }
            if setting.domain == "com.apple.screencapture", setting.key == "location" {
                try FileManager.default.createDirectory(atPath: setting.resolvedValue, withIntermediateDirectories: true)
            }
            lines.append("Writing: \(setting.description). If stopped here, check this preference again.")
            progress?(lines.joined(separator: "\n"))
            let wrote = try runner.run("/usr/bin/defaults", setting.arguments("write"))
            let after = try inspect(setting)
            let matches = after.status == "set"
            if plain { preferenceResult?(PreferenceResult(id: setting.id, current: after.current, status: wrote.code == 0 && matches ? "set" : "failed", detail: wrote.output + after.detail, checkedAt: after.checkedAt)) }
            if wrote.code == 0 && matches { lines.append("✓ Verified · \(setting.description)") }
            else { failed[row.id] = wrote.output + after.detail; lines.append("✕ Could not verify · \(setting.description)\n  \(wrote.output)\(setting.protected ? "\n  Turn on Full Disk Access for ArfanReset1, then quit and reopen the app. Or set it by hand in System Settings." : "")") }
            progress?(lines.joined(separator: "\n"))
        }
        // A choice row reports once, after all of its keys.
        for row in rows where row.options != nil {
            let result = try inspectRow(row, option: choices[row.id])
            preferenceResult?(failed[row.id].map { PreferenceResult(id: row.id, current: result.current, status: "failed", detail: $0, checkedAt: result.checkedAt) } ?? result)
        }
        lines += ["", "\(rows.count - failed.count) verified or already set. \(failed.count) failed.", "Next: choose Restart Finder & Dock to refresh those apps. Some settings need a logout. Read-back confirms a value was saved, but macOS can ignore a key it no longer supports."]
        if let keyboard = selected.first(where: { $0.key == "virtualKeyboardOnOff" }), keyboard.matches(try read(keyboard)) {
            let opened = try runner.run("/usr/bin/open", ["-a", "/System/Library/CoreServices/AssistiveControl.app"])
            lines.append(opened.code == 0 ? "Accessibility Keyboard launch requested." : "Keyboard preference is on, but AssistiveControl could not open: " + opened.output)
        }
        return lines.joined(separator: "\n")
    }
    func restore() throws -> String {
        let backup = try JSONDecoder().decode(PreferenceBackup.self, from: Data(contentsOf: backupURL))
        var lines = ["Restoring the last preference backup · \(backup.date.formatted())", ""]
        progress?(lines.joined(separator: "\n"))
        for entry in backup.entries {
            try runner.checkCancellation()
            let s = entry.setting
            let old = try entry.previous.map { try PropertyListSerialization.propertyList(from: $0, format: nil) as! [String: Any] }?["value"]
            let host = s.currentHost == true ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
            let domain = s.domain == "NSGlobalDomain" ? kCFPreferencesAnyApplication : s.domain as CFString
            let synced: Bool
            if let testPreferenceWriter { synced = testPreferenceWriter(s, old) }
            else {
                CFPreferencesSetValue(s.key as CFString, old as CFPropertyList?, domain, kCFPreferencesCurrentUser, host)
                synced = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, host)
            }
            lines.append("Restore written: \(s.description). Verifying…")
            progress?(lines.joined(separator: "\n"))
            let exported = try runner.run("/usr/bin/defaults", s.scope + ["export", s.domain, "-"])
            let dict = (try? PropertyListSerialization.propertyList(from: Data(exported.output.utf8), format: nil)) as? [String: Any]
            let actual = dict?[s.key]
            let verified = old == nil ? (actual == nil && (exported.code == 0 || exported.output.contains("does not exist"))) : (actual.map { NSDictionary(dictionary: ["value": $0]).isEqual(to: ["value": old!]) } ?? false)
            preferenceResult?(try inspect(s))
            lines.append("\(synced && verified ? "✓ Restored" : "✕ Could not verify restore") · \(s.description)")
            progress?(lines.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n") + "\n\nNext: restart Finder & Dock, or log out, to refresh the apps these settings belong to."
    }
    func tools() throws -> String {
        var lines = ["Read-only check · \(installers.count) tools", ""]
        for installer in installers {
            let result = try checkTool(installer.id)
            toolResult?(result)
            lines.append(result.logEntry(name: installer.name))
            progress?(lines.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }
    /// Read only: opens nothing for writing, changes nothing and never triggers a macOS consent prompt.
    func permissions(shell: URL, runner: CommandRunner, home: String = NSHomeDirectory()) throws -> [Permission] {
        let fm = FileManager.default
        var list: [Permission] = []
        switch Permissions.fullDiskAccess(home: home) {
        case true?: list.append(Permission(id: "fda", name: "Full Disk Access", status: "granted", detail: "ArfanReset1 can write the protected Accessibility preferences and measure Mail, Safari and other protected folders.", usedBy: "Accessibility & gestures · Disk usage", settings: "privacy"))
        case false?: list.append(Permission(id: "fda", name: "Full Disk Access", status: "missing", detail: "Turn on ArfanReset1 in Full Disk Access, then quit and reopen the app. Without it, the Zoom and Accessibility Keyboard preferences cannot be applied, and Disk usage skips protected folders. A rebuilt copy of this app may need it turned on again.", usedBy: "Accessibility & gestures · Disk usage", settings: "privacy"))
        case nil: list.append(Permission(id: "fda", name: "Full Disk Access", status: "unknown", detail: "Could not tell from the protected files on this Mac. If Accessibility preferences fail to apply, turn on ArfanReset1 in Full Disk Access.", usedBy: "Accessibility & gestures · Disk usage", settings: "privacy"))
        }
        let groups = try runner.run("/usr/bin/id", ["-Gn"])
        let admin = groups.code == 0 ? groups.output.split(whereSeparator: \.isWhitespace).contains("admin") : nil
        list.append(Permission(id: "admin", name: "Administrator account", status: admin.map { $0 ? "granted" : "missing" } ?? "unknown",
                               detail: admin == true ? "\(NSUserName()) is an administrator, so installers can use sudo after you type your password in Terminal." : admin == false ? "\(NSUserName()) is a standard user. The Software Update script and Homebrew use sudo. Sign in as an administrator, or ask one to run them." : "Could not read your groups: " + groups.output,
                               usedBy: "Command Line Tools · Homebrew", settings: "users"))
        let terminal = fm.fileExists(atPath: "/System/Applications/Utilities/Terminal.app")
        list.append(Permission(id: "terminal", name: "Terminal", status: terminal ? "granted" : "missing",
                               detail: terminal ? "Installers open in Terminal so you can review and answer their prompts there." : "Terminal.app was not found in /System/Applications/Utilities, so installers cannot open.",
                               usedBy: "Command Line Tools · CLI tools · Homebrew · Optional CLI tools"))
        // Zsh setup writes a temp file beside the resolved .zshrc and a backups folder beside the requested one.
        let folders = Set([shell.deletingLastPathComponent().path, shell.resolvingSymlinksInPath().deletingLastPathComponent().path])
        let blocked = folders.sorted().filter { !Permissions.writable($0) }
        let rcLocked = fm.fileExists(atPath: shell.path) && !fm.isWritableFile(atPath: shell.resolvingSymlinksInPath().path)
        list.append(Permission(id: "zsh", name: "Write your .zshrc", status: blocked.isEmpty && !rcLocked ? "granted" : "missing",
                               detail: blocked.isEmpty && !rcLocked ? "The app can back up and replace \(shell.path)." : "Cannot write \(rcLocked ? shell.path : blocked.joined(separator: ", ")). Check its owner and permissions, or choose another shell folder on the faster zsh startup page.",
                               usedBy: "faster zsh startup"))
        let data = Permissions.writable(support.path)
        list.append(Permission(id: "support", name: "App data folder", status: data ? "granted" : "missing",
                               detail: data ? "Backups, Terminal scripts, the run log and saved scans go in \(support.path)." : "Cannot write \(support.path), so preference backups cannot be saved and Apply will stop before changing anything.",
                               usedBy: "macOS defaults · Accessibility & gestures · Run log · Disk usage"))
        return list
    }
    func diskScan(path: String) throws -> DiskScan {
        guard DiskUsage.isAllowed(path) else { throw SetupError.message("Disk usage only reads inside your home folder.") }
        // Fixed executable and flags; `path` is validated above and always starts with "/".
        let result = try runner.run("/usr/bin/du", ["-k", "-x", "-d", "1", path], timeout: 240)
        let parsed = DiskUsage.parse(result.output, root: path)
        guard parsed.total > 0 || result.code == 0 else { throw SetupError.message("The scan could not read this folder. Full Disk Access may be needed.") }
        return DiskUsage.scan(path: path, parsed: parsed)
    }
}

enum Permissions {
    /// macOS has no API to ask; the standard probe is opening a file only Full Disk Access can read.
    /// nil when none of the probe files exist on this Mac.
    static func fullDiskAccess(home: String) -> Bool? {
        for probe in ["/Library/Application Support/com.apple.TCC/TCC.db", "/Library/Safari", "/Library/Mail"] {
            let fd = open(home + probe, O_RDONLY)
            if fd >= 0 { close(fd); return true }
            if errno == EPERM || errno == EACCES { return false }
        }
        return nil
    }
    /// An existing folder must be writable; a missing one must be creatable inside its nearest existing parent.
    static func writable(_ path: String) -> Bool {
        var url = URL(fileURLWithPath: path)
        while !FileManager.default.fileExists(atPath: url.path), url.path != "/" { url.deleteLastPathComponent() }
        return FileManager.default.isWritableFile(atPath: url.path)
    }
}

struct DiskEntry: Codable { let name, path: String; let bytes: Int; let isDirectory: Bool }
struct DiskScan: Codable {
    let path, home: String
    let parent: String?
    let bytes: Int
    let entries: [DiskEntry]
    let moreCount, moreBytes, unreadable: Int
    let volumeName: String
    let volumeTotal, volumeAvailable: Int
    /// Seconds since 1970; shown as "Scanned …" so a saved result is never mistaken for a live one.
    let scannedAt: TimeInterval
    /// Every folder and every file in this folder, so the page can list them apart. Absent in scans saved before
    /// the split view; `entries` then holds only the largest items overall.
    var folders: DiskKind? = nil
    var files: DiskKind? = nil
    var itemCount: Int { folders.map { $0.count + (files?.count ?? 0) } ?? entries.count + moreCount }
}
struct DiskKind: Codable { let count, bytes: Int }

/// Saved scans by folder, so opening a folder again does not run `du`. Only Refresh rescans.
struct DiskCache {
    static let limit = 150
    private(set) var scans: [String: DiskScan] = [:]

    init(url: URL? = nil, home: String = DiskUsage.home) {
        guard let url, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([String: DiskScan].self, from: data) else { return }
        scans = saved.filter { DiskUsage.isAllowed($0.key, home: home) }   // folders that were deleted or moved drop out
    }

    mutating func store(_ scan: DiskScan) {
        scans[scan.path] = scan
        guard scans.count > Self.limit else { return }
        let oldest = scans.values.filter { $0.path != scan.home && $0.path != scan.path }.sorted { $0.scannedAt < $1.scannedAt }
        for old in oldest.prefix(scans.count - Self.limit) { scans[old.path] = nil }
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(scans).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Read-only helpers for the Disk usage page. Nothing here deletes or moves files.
enum DiskUsage {
    static let limit = 60
    static var home: String { NSHomeDirectory() }

    /// Only the home folder and what is inside it; the page cannot ask for anything else.
    static func isAllowed(_ path: String, home: String = DiskUsage.home) -> Bool {
        guard path.hasPrefix("/"), !path.contains("\0") else { return false }
        let clean = URL(fileURLWithPath: path).standardizedFileURL.path
        guard clean == path || clean + "/" == path else { return false }
        return (clean == home || clean.hasPrefix(home + "/")) && FileManager.default.fileExists(atPath: clean)
    }

    /// `du -d 1` lists the folder itself and each sub-folder; files are read from the filesystem in `entries`.
    static func parse(_ output: String, root: String) -> (total: Int, sizes: [String: Int], unreadable: Int) {
        var total = 0, unreadable = 0
        var sizes: [String: Int] = [:]
        let base = root.hasSuffix("/") && root.count > 1 ? String(root.dropLast()) : root
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let kilobytes = Int(parts[0]) else { if line.hasPrefix("du:") { unreadable += 1 }; continue }
            let path = String(parts[1])
            if path == root || path == base { total = kilobytes * 1024 } else if path.hasPrefix(base + "/") { sizes[path] = kilobytes * 1024 }
        }
        return (total, sizes, unreadable)
    }

    /// Every item in the folder, hidden ones included, largest first. Symlinks are listed but never followed.
    static func entries(root: String, sizes: [String: Int]) -> [DiskEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: Array(keys), options: [])) ?? []
        let list = urls.map { url -> DiskEntry in
            let values = try? url.resourceValues(forKeys: keys)
            let folder = values?.isDirectory == true && values?.isSymbolicLink != true
            // Build the path from the scanned root; the URL's own path may be re-resolved (/var vs /private/var).
            let path = (root.hasSuffix("/") ? root : root + "/") + url.lastPathComponent
            let bytes = folder ? (sizes[path] ?? 0) : (values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            return DiskEntry(name: url.lastPathComponent, path: path, bytes: bytes, isDirectory: folder)
        }
        return list.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func scan(path: String, parsed: (total: Int, sizes: [String: Int], unreadable: Int)) -> DiskScan {
        let url = URL(fileURLWithPath: path)
        let all = entries(root: path, sizes: parsed.sizes)
        let volume = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        // The largest `limit` folders and the largest `limit` files: that covers the largest `limit` overall for the
        // combined list, and gives each list of the split view its own top items. `more` counts the combined list.
        let folders = all.filter(\.isDirectory), files = all.filter { !$0.isDirectory }
        let kept = Set(folders.prefix(limit).map(\.path) + files.prefix(limit).map(\.path))
        let rest = all.dropFirst(limit)
        let total = { (list: [DiskEntry]) in list.reduce(0) { $0 + $1.bytes } }
        return DiskScan(path: path, home: home, parent: path == home ? nil : url.deletingLastPathComponent().path,
                        bytes: max(parsed.total, total(all)), entries: all.filter { kept.contains($0.path) },
                        moreCount: rest.count, moreBytes: total(Array(rest)), unreadable: parsed.unreadable,
                        volumeName: volume?.volumeName ?? "This Mac", volumeTotal: volume?.volumeTotalCapacity ?? 0,
                        volumeAvailable: Int(volume?.volumeAvailableCapacityForImportantUsage ?? 0),
                        scannedAt: Date().timeIntervalSince1970,
                        folders: DiskKind(count: folders.count, bytes: total(folders)), files: DiskKind(count: files.count, bytes: total(files)))
    }
}
