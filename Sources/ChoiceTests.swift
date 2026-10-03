import Foundation

enum ChoiceTests {
    static func run(resources: URL, temp: URL) throws {
        let require = SelfTests.require
        let runner = CommandRunner()
        let engine = try SetupEngine(resources: resources, support: temp.appendingPathComponent("choice-support"), runner: runner)
        let appearance = engine.settings.first { $0.id == "appearance" }!, icons = engine.settings.first { $0.id == "icon-style" }!
        let index = engine.settings.firstIndex { $0.id == "appearance" }!
        try require(engine.settings[index + 1].id == "icon-style" && engine.settings[index - 1].group == "Windows" && engine.settings[index + 2].group == "Finder", "A choice takes the imported row's place, and the next choice follows it in the group")
        try require(!engine.settings.contains { $0.options == nil && $0.key == "AppleInterfaceStyleSwitchesAutomatically" }, "The fixed row for a choice's key is gone")
        try require(appearance.option(nil)?.id == "dark" && icons.option("nonsense")?.id == "dark" && icons.option("clear-auto")?.label == "Clear (auto)", "Dark is the default option; an unknown pick falls back to it")
        let dark = appearance.components(option: "dark")
        try require(dark.map(\.key) == ["AppleInterfaceStyle", "AppleInterfaceStyleSwitchesAutomatically"] && dark.map(\.type) == ["string", "delete"], "An option expands to one setting per key")
        try require(try dark[1].arguments("write") == ["delete", "NSGlobalDomain", "AppleInterfaceStyleSwitchesAutomatically"] && dark[1].matches(nil) && !dark[1].matches("1"), "Delete removes the key and matches only when it is absent")
        for message in ["The domain/default pair does not exist", "Error: Could not find key 'AppleInterfaceStyleSwitchesAutomatically' in domain 'kCFPreferencesAnyApplication'."] {
            let missing = CommandResult(code: 1, output: message)
            try require(SetupEngine.status(dark[1], missing) == "set" && SetupEngine.status(dark[0], missing) == "change", "Both defaults missing-key messages describe absence, not a read failure")
        }
        do { _ = try SetupEngine.merge([], choices: [Setting(id: "bad", section: "defaults", group: "G", domain: "D", key: "K", type: "choice", value: "missing", description: "Bad", options: [.init(id: "a", label: "A", writes: [.init(key: "K", type: "string", value: "x")])])]); throw SetupError.message("Accepted a choice without its default") }
        catch SetupError.message(let message) { try require(message.contains("Invalid choice"), "A choice must name an existing default option") }

        // Simulated defaults backend: nothing here reads or writes real preferences.
        var domain: [String: Any] = ["AppleInterfaceStyle": "Dark", "AppleIconAppearanceTheme": "RegularDark"]
        var writes: [[String]] = []
        runner.testExecutor = { executable, args in
            try require(executable == "/usr/bin/defaults", "Choices use a fixed executable")
            switch args[0] {
            case "export":
                return CommandResult(code: 0, output: String(decoding: try PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0), as: UTF8.self))
            case "read":
                guard let value = domain[args[2]] else { return CommandResult(code: 1, output: "Error: Could not find key '\(args[2])' in domain 'kCFPreferencesAnyApplication'.") }
                return CommandResult(code: 0, output: (value as? Bool).map { $0 ? "1" : "0" } ?? String(describing: value))
            case "delete": writes.append(args); domain[args[2]] = nil
            default: writes.append(args); domain[args[2]] = args[3] == "-bool" ? args[4] == "true" : args[4]
            }
            return CommandResult(code: 0, output: "")
        }
        var results: [String: PreferenceResult] = [:]
        engine.preferenceResult = { results[$0.id] = $0 }
        let now = try engine.inspectRow(appearance, option: "dark")
        try require(now.status == "set" && now.current == "Dark", "Dark with no automatic key is already Dark")
        let light = try engine.inspectRow(appearance, option: "light")
        try require(light.status == "change" && light.current == "Dark", "Another option is a proposed change and names the current one")
        _ = try engine.check([appearance, icons], choices: ["appearance": "auto", "icon-style": "dark"])
        try require(results["appearance"]?.status == "change" && results["icon-style"]?.status == "set" && writes.isEmpty, "Check reports once per row and stays read only")

        let applied = try engine.apply([appearance, icons], choices: ["appearance": "light", "icon-style": "clear-auto"])
        try require(domain["AppleInterfaceStyle"] == nil && domain["AppleIconAppearanceTheme"] as? String == "ClearAutomatic" && applied.contains("2 verified or already set. 0 failed."), "Apply removes and writes the chosen option's keys, and counts rows")
        try require(writes == [["delete", "NSGlobalDomain", "AppleInterfaceStyle"], ["write", "NSGlobalDomain", "AppleIconAppearanceTheme", "-string", "ClearAutomatic"]], "Only keys that differ are written; an absent key is not deleted again")
        try require(results["appearance"]?.status == "set" && results["appearance"]?.current == "Light" && results["icon-style"]?.current == "Clear (auto)" && results.keys.allSatisfy { !$0.contains(".") }, "A choice row reports once, under its own id")
        let backup = try JSONDecoder().decode(PreferenceBackup.self, from: Data(contentsOf: engine.backupURL))
        try require(backup.entries.map(\.setting.key) == ["AppleInterfaceStyle", "AppleInterfaceStyleSwitchesAutomatically", "AppleIconAppearanceTheme"] && backup.entries[0].previous != nil && backup.entries[1].previous == nil, "The backup holds every key the options touch, present or absent")
        engine.testPreferenceWriter = { setting, value in domain[setting.key] = value; return true }
        let restored = try engine.restore()
        try require(!restored.contains("✕") && domain["AppleInterfaceStyle"] as? String == "Dark" && domain["AppleIconAppearanceTheme"] as? String == "RegularDark" && domain["AppleInterfaceStyleSwitchesAutomatically"] == nil, "Restore puts back every key, including one that was removed")

        _ = try engine.apply([appearance], choices: ["appearance": "auto"])
        try require(domain["AppleInterfaceStyleSwitchesAutomatically"] as? Bool == true && domain["AppleInterfaceStyle"] as? String == "Dark" && (try engine.inspectRow(appearance, option: "auto")).current == "Auto", "Auto turns on automatic switching and leaves the style key alone")
        domain["AppleIconAppearanceTheme"] = "SomethingNew"
        try require((try engine.inspectRow(icons, option: "dark")).current == "Something else", "A value outside the options is named as such")
        runner.testExecutor = { _, args in args[0] == "read" ? CommandResult(code: 1, output: "Permission denied") : CommandResult(code: 0, output: "") }
        let unreadable = try engine.inspectRow(icons, option: "dark")
        try require(unreadable.status == "failed" && unreadable.current == nil && unreadable.detail.contains("Permission denied"), "An unreadable key is a failure, not a change")
        runner.testExecutor = nil
        print("Choice tests: catalog placement, default option, key removal, read-only check, apply, backup, restore and unknown values passed.")
    }
}
