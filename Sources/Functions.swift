import Foundation

struct ShellFunction: Codable {
    let id, name, description, usage, source: String
    let requirements: [String]
    var code: String = ""
}
struct FunctionStatus: Codable {
    let id, status, detail: String
    let missing: [String]
}
struct FunctionPreview: Codable { let id: String; let preview: ShellPreview }

enum ShellFunctions {
    static func load(resources: URL) throws -> [ShellFunction] {
        struct Entry: Decodable {
            let id, name, description, usage, source: String
            let requirements: [String]
        }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: resources.appendingPathComponent("Config/functions.json")))
        guard Set(entries.map(\.id)).count == entries.count, Set(entries.map(\.name)).count == entries.count else { throw SetupError.message("Duplicate shell function names or IDs") }
        return try entries.map { entry in
            guard entry.id.range(of: #"^[a-z][a-z0-9_-]*$"#, options: .regularExpression) != nil,
                  entry.name.range(of: #"^[a-zA-Z_][a-zA-Z0-9_]*$"#, options: .regularExpression) != nil,
                  entry.source.range(of: #"^[a-zA-Z0-9_-]+\.zsh$"#, options: .regularExpression) != nil else { throw SetupError.message("Invalid shell function catalog entry") }
            let code = try String(contentsOf: resources.appendingPathComponent("Functions/" + entry.source), encoding: .utf8)
            return ShellFunction(id: entry.id, name: entry.name, description: entry.description, usage: entry.usage, source: entry.source, requirements: entry.requirements, code: code)
        }
    }
    static func updated(_ original: String, function: ShellFunction) throws -> String {
        let start = "# >>> arfanreset1 function \(function.id) >>>"
        let end = "# <<< arfanreset1 function \(function.id) <<<"
        let count = original.components(separatedBy: start).count - 1
        guard count <= 1, count == original.components(separatedBy: end).count - 1 else { throw SetupError.message("Ambiguous markers for \(function.name). Nothing changed.") }
        var remainder = original
        var range: Range<String.Index>?
        if let begin = original.range(of: start), let finish = original.range(of: end) {
            guard begin.lowerBound < finish.lowerBound,
                  (begin.lowerBound == original.startIndex || original[original.index(before: begin.lowerBound)] == "\n"),
                  (finish.upperBound == original.endIndex || original[finish.upperBound] == "\n") else { throw SetupError.message("Invalid markers for \(function.name). Nothing changed.") }
            let upper = finish.upperBound < original.endIndex ? original.index(after: finish.upperBound) : finish.upperBound
            range = begin.lowerBound..<upper
            remainder.removeSubrange(range!)
        }
        // Do not silently override definitions outside this app's block. A shell parser is not run here.
        let name = NSRegularExpression.escapedPattern(for: function.name)
        let pattern = "(?m)^\\s*(?:function\\s+\(name)(?:\\s*\\(\\s*\\))?(?=\\s|\\{)|\(name)\\s*\\(\\s*\\))"
        let regex = try NSRegularExpression(pattern: pattern)
        let definitions = regex.numberOfMatches(in: remainder, range: NSRange(remainder.startIndex..., in: remainder))
        // An exact existing snippet needs no duplicate block or migration.
        if range == nil, definitions == 1, remainder.contains(function.code.trimmingCharacters(in: .newlines)) { return original }
        guard definitions == 0 else { throw SetupError.message("Your .zshrc already defines \(function.name) outside this app’s block. Remove or rename that definition, then check again. Nothing changed.") }
        let block = start + "\n" + function.code + (function.code.hasSuffix("\n") ? "" : "\n") + end + "\n"
        if let range { var result = original; result.replaceSubrange(range, with: block); return result }
        return original + (original.isEmpty || original.hasSuffix("\n") ? "" : "\n") + block
    }
    static func status(_ functions: [ShellFunction], at target: URL, home: String = NSHomeDirectory()) -> [FunctionStatus] {
        let exists = FileManager.default.fileExists(atPath: target.path)
        let original = exists ? try? String(contentsOf: target, encoding: .utf8) : ""
        return functions.map { function in
            let missing = function.requirements.filter { !FileManager.default.fileExists(atPath: $0.replacingOccurrences(of: "~/", with: home + "/")) }
            guard let original else { return FunctionStatus(id: function.id, status: "conflict", detail: "Could not read .zshrc. Check its permissions.", missing: missing) }
            do {
                let proposed = try updated(original, function: function)
                return FunctionStatus(id: function.id, status: proposed == original ? "installed" : "available", detail: proposed == original ? "Your .zshrc already has this exact function, so nothing is added twice. Open a new Terminal to use it." : "Preview the change before adding it to .zshrc.", missing: missing)
            } catch { return FunctionStatus(id: function.id, status: "conflict", detail: error.localizedDescription, missing: missing) }
        }
    }
}
