import Foundation

struct AccessibilityAction: Codable {
    let id, name, description, settingsID, path, scriptName, help: String
    var prompt: String {
        "Use computer use in the Codex desktop app to enable \(name) on this Mac. Open System Settings → \(path). Read the current switch state. If it is off, click it once; if already on, leave it on. Verify from fresh UI state that \(name) is on. Change only this setting. Do not use shell commands, defaults writes, or AppleScript. If computer use is unavailable or a permission is needed, explain what I need to enable and stop. I intend to run this chat with GPT-6 Luna (gpt-6-luna), selected in the model picker."
    }
    static let all: [AccessibilityAction] = [
        .init(id: "speech", name: "Speak selection", description: "Hear selected text read aloud. After enabling it, select text and use Option + Esc (the default shortcut).", settingsID: "speech", path: "Accessibility → Read & Speak → Speak selection", scriptName: "enable-speak-selection.sh", help: "https://support.apple.com/guide/mac-help/mh27448/mac"),
        .init(id: "keyboard", name: "Accessibility Keyboard", description: "Show an onscreen keyboard to type and interact with your Mac.", settingsID: "keyboard", path: "Accessibility → Keyboard → Accessibility Keyboard", scriptName: "enable-accessibility-keyboard.sh", help: "https://support.apple.com/guide/mac-help/mchlc74c1c9f/mac")
    ]
    static func codexURL(for item: AccessibilityAction) -> URL {
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "new"
        components.queryItems = [URLQueryItem(name: "prompt", value: item.prompt)]
        return components.url!
    }
    func cliCommand(script: String) -> String {
        let prompt = "Enable only \(name) on this Mac by running /bin/bash enable-setting.sh in this working directory. Read that bundled script first; do not modify it. It checks the exact UI switch, leaves it on if already enabled, clicks once if off, and verifies the result. Request execution approval if the sandbox blocks UI automation. If macOS permissions are missing, explain how to allow Terminal Accessibility and Automation access and stop. Do not change permissions yourself, write defaults, install tools, or change any other setting. Report success only if the script reports an already-on or verified-on result."
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
        return """
        set -euo pipefail
        export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
        if ! command -v codex >/dev/null 2>&1; then
          printf '%s\\n' 'Codex CLI not found. Install it from the CLI tools page, then retry.'
          exit 1
        fi
        if ! codex login status; then
          printf '%s\\n' 'Sign in with: codex login. Then retry this method.'
          exit 1
        fi
        task_dir=$(mktemp -d "${TMPDIR:-/tmp}/arfanreset-codex.XXXXXX")
        printf '%s\\n' \(quote(script)) > "$task_dir/enable-setting.sh"
        chmod 600 "$task_dir/enable-setting.sh"
        printf 'Task folder: %s\\n' "$task_dir"
        codex --model gpt-6-luna --sandbox workspace-write --ask-for-approval on-request --cd "$task_dir" \(quote(prompt))
        """
    }
}
