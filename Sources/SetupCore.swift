import Foundation
import CoreFoundation

struct Setting: Codable {
    let id, section, group, domain, key, type, value, description: String
    var currentHost: Bool? = nil
    var protected: Bool { domain == "com.apple.universalaccess" }
    var resolvedValue: String { value.replacingOccurrences(of: "~/", with: NSHomeDirectory() + "/") }
    var scope: [String] { currentHost == true ? ["-currentHost"] : [] }
    func arguments(_ verb: String) throws -> [String] {
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
}

struct Installer: Codable { let id, name, command, guide: String; let optional: Bool }
struct Guide: Codable { let file, title: String }
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
        if cancelled { lock.unlock(); throw SetupError.message("Stopped by you. Completed changes remain in the backup.") }
        do { try process.run() } catch { lock.unlock(); throw error }
        active = process
        lock.unlock()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); deadline.cancel()
        lock.lock(); active = nil; let stopped = cancelled; lock.unlock()
        if stopped { throw SetupError.message("Stopped by you. Completed changes remain in the backup.") }
        let output = String(decoding: data.prefix(500_000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandResult(code: process.terminationStatus, output: output)
    }
}

enum ShellSetup {
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
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: temp.path)
        // POSIX rename replaces atomically within the same directory and keeps symlinks intact.
        guard rename(temp.path, rc.path) == 0 else { throw SetupError.message("Could not replace .zshrc: \(String(cString: strerror(errno)))") }
        return message + "Updated: \(rc.path)\nOpen a new Terminal. First Tab and first Node command initialize once. Custom framework and plugin code stays as it was."
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
    let shell: ShellConfig
    var testPreferenceWriter: ((Setting, Any?) -> Bool)?
    var backupURL: URL { support.appendingPathComponent("preferences-latest.json") }
    init(resources: URL, support: URL, runner: CommandRunner = CommandRunner()) throws {
        self.runner = runner
        self.resources = resources; self.support = support
        func load<T: Decodable>(_ name: String) throws -> T {
            try JSONDecoder().decode(T.self, from: Data(contentsOf: resources.appendingPathComponent("Config/" + name)))
        }
        settings = try load("settings.json"); installers = try load("installers.json")
        guides = try load("guides.json"); shell = try load("shell.json")
    }
    func read(_ setting: Setting) throws -> String? {
        let result = try runner.run("/usr/bin/defaults", setting.arguments("read"))
        return result.code == 0 ? result.output : nil
    }
    func check(_ selected: [Setting]) throws -> String {
        var lines = ["Read-only check · \(selected.count) preferences", ""]
        for setting in selected {
            let value = try read(setting)
            lines.append("\(setting.matches(value) ? "✓ Already set" : "• Would change") · \(setting.description)\n  \(setting.domain) \(setting.key): \(value ?? "unset or unreadable") → \(setting.resolvedValue)")
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
    func apply(_ selected: [Setting]) throws -> String {
        guard !selected.isEmpty else { throw SetupError.message("Select at least one preference.") }
        let backup = try capture(selected)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        let archive = support.appendingPathComponent("preferences-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json")
        try data.write(to: archive, options: .atomic)
        try data.write(to: backupURL, options: .atomic)
        var lines = ["Backup: \(archive.path)", ""]
        var failed = 0
        for setting in selected {
            if setting.matches(try read(setting)) { lines.append("✓ Already set · \(setting.description)"); continue }
            if setting.domain == "com.apple.screencapture", setting.key == "location" {
                try FileManager.default.createDirectory(atPath: setting.resolvedValue, withIntermediateDirectories: true)
            }
            let wrote = try runner.run("/usr/bin/defaults", setting.arguments("write"))
            let matches = setting.matches(try read(setting))
            if wrote.code == 0 && matches { lines.append("✓ Verified · \(setting.description)") }
            else { failed += 1; lines.append("✕ Could not verify · \(setting.description)\n  \(wrote.output)\(setting.protected ? "\n  Enable Full Disk Access for ArfanReset1, quit and reopen the app; or set it in System Settings." : "")") }
        }
        lines += ["", "\(selected.count - failed) verified or already set; \(failed) failed.", "Use Restart Finder & Dock to refresh those apps. Some settings require logging out. Preference read-back verifies storage; macOS may ignore unsupported keys."]
        if let keyboard = selected.first(where: { $0.key == "virtualKeyboardOnOff" }), keyboard.matches(try read(keyboard)) {
            let opened = try runner.run("/usr/bin/open", ["-a", "/System/Library/CoreServices/AssistiveControl.app"])
            lines.append(opened.code == 0 ? "Accessibility Keyboard launch requested." : "Keyboard preference is on, but AssistiveControl could not open: " + opened.output)
        }
        return lines.joined(separator: "\n")
    }
    func restore() throws -> String {
        let backup = try JSONDecoder().decode(PreferenceBackup.self, from: Data(contentsOf: backupURL))
        var lines = ["Restoring the last preference backup · \(backup.date.formatted())", ""]
        for entry in backup.entries {
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
            let exported = try runner.run("/usr/bin/defaults", s.scope + ["export", s.domain, "-"])
            let dict = (try? PropertyListSerialization.propertyList(from: Data(exported.output.utf8), format: nil)) as? [String: Any]
            let actual = dict?[s.key]
            let verified = old == nil ? (actual == nil && (exported.code == 0 || exported.output.contains("does not exist"))) : (actual.map { NSDictionary(dictionary: ["value": $0]).isEqual(to: ["value": old!]) } ?? false)
            lines.append("\(synced && verified ? "✓ Restored" : "✕ Could not verify restore") · \(s.description)")
        }
        return lines.joined(separator: "\n") + "\n\nRestart Finder & Dock or log out to refresh the relevant apps."
    }
    func tools() throws -> String {
        var lines = ["\(ProcessInfo.processInfo.hostName) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", ""]
        let clt = try runner.run("/usr/bin/xcode-select", ["-p"])
        lines.append("Command Line Tools: " + (clt.code == 0 ? clt.output : "Not installed"))
        for (name, args) in [("deno", ["--version"]), ("uv", ["--version"]), ("brew", ["--version"]), ("atuin", ["--version"]), ("claude", ["--version"]), ("codex", ["--version"]), ("bun", ["--version"]), ("opencode", ["--version"]), ("go", ["version"]), ("zig", ["version"]), ("rustc", ["--version"])] {
            let found = try runner.run("/bin/zsh", ["-f", "-c", "command -v " + name])
            if found.code == 0 && found.output.hasPrefix("/") {
                let version = try runner.run(found.output, args, timeout: 8)
                lines.append("\(name): \(found.output)\n  \(version.code == 0 ? version.output.components(separatedBy: "\n").prefix(2).joined(separator: " · ") : "Version check failed: " + version.output)")
            } else { lines.append("\(name): Not found in standard install paths") }
        }
        let nvm = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".nvm")
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvm.appendingPathComponent("versions/node").path)) ?? []
        lines.append("nvm: " + (FileManager.default.fileExists(atPath: nvm.appendingPathComponent("nvm.sh").path) ? "Installed · Node versions: " + versions.sorted().joined(separator: ", ") : "Not found"))
        return lines.joined(separator: "\n")
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
}

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
        let shown = Array(all.prefix(limit)), rest = all.dropFirst(limit)
        return DiskScan(path: path, home: home, parent: path == home ? nil : url.deletingLastPathComponent().path,
                        bytes: max(parsed.total, all.reduce(0) { $0 + $1.bytes }), entries: shown,
                        moreCount: rest.count, moreBytes: rest.reduce(0) { $0 + $1.bytes }, unreadable: parsed.unreadable,
                        volumeName: volume?.volumeName ?? "This Mac", volumeTotal: volume?.volumeTotalCapacity ?? 0,
                        volumeAvailable: Int(volume?.volumeAvailableCapacityForImportantUsage ?? 0),
                        scannedAt: Date().timeIntervalSince1970)
    }
}
