# ArfanReset1

A small native macOS app for the first things to do on a new Mac or after a reset.
Swift/AppKit hosts a bundled HTML/CSS/JavaScript interface in WKWebView, like
ArfanView1 and ArfanMenu3. No local server, frontend build, package manager, or
runtime is needed to use the downloaded app. Supports macOS 14 and newer.

The initial **total window frame is 1200 × 860 logical points**, with its top-left
at **100,80** from the main screen's top-left. The exact initial frame is retained
even on a smaller display; resize or zoom the window if it extends below your screen.

## Use

Open `build/ArfanReset1.app`, or unzip the distribution and drag the app into
Applications. Follow the six setup steps at your own pace:

1. Open Apple's Command Line Tools installer, then verify the installation.
2. Review and run the CLI installers you want: Deno, uv, Atuin, Claude Code,
   Codex CLI, Node through nvm, Bun, and OpenCode.
3. Install Homebrew and configure its shell PATH.
4. Check and apply selected Finder, Dock, keyboard, screenshot and other defaults.
5. Set Mission Control gestures, trackpad zoom and Accessibility Keyboard.
6. Back up `.zshrc` and install the deferred nvm/completion setup.

Optional Go, Zig and Rust installers, a native read-only disk scan, and all ten
original reset1 guides are included. Installer commands appear under **Review
installer command** and run in Terminal for interactive/password prompts. Terminal
launch does not mark installation complete; use **Check this Mac** afterwards.
Checklist marks are manual and saved by the native app.

**Check only** reads preferences without changing them. **Apply** backs up exact,
typed values first, then writes and reads each selected value back. **Restore last
preference backup** restores only the keys from that run, including removing keys
that were previously absent. Each Apply also keeps a timestamped backup. Finder
and Dock restart only when you select that action. Some preferences require logout
or are ignored by particular macOS releases; read-back verifies preference storage.

Accessibility preferences start unselected. If macOS refuses them, use System
Settings to set them manually, or give **ArfanReset1** Full Disk Access and restart
the app before retrying. Reopen System Settings to refresh cached values.

Zsh setup preserves unrelated lines, symlinks and permissions, validates syntax,
and writes atomically. It supports HOME or a folder you select for ZDOTDIR. The
exact backup path is in the run log; to undo, restore that backup to your `.zshrc`.
Custom frameworks, multiline loader blocks and plugins are preserved.

App state is in UserDefaults for `com.arfan.arfanreset1`. Preference backups,
Terminal scripts, the last run log, and saved Disk usage scans (`disk-cache.json`, readable only
by you) are in `~/Library/Application Support/ArfanReset1/`. Disk usage opens a folder you have
already scanned instantly; use **Refresh** to rescan the folder you are viewing. Zsh backups live in the `backups/`
folder beside the selected `.zshrc`.

## Build and package

Only Apple's Command Line Tools are needed to build; no uv or Deno:

```sh
./build.sh                          # Current architecture
./build.sh --selftest               # Build and isolated regression checks
./build.sh --universal --zip        # Apple Silicon + Intel distribution ZIP
./build.sh --install                # Explicitly install into /Applications and open
```

Root tasks: `deno task build:arfanreset1`, `test:arfanreset1`,
`package:arfanreset1`, and `install:arfanreset1`.

The build is ad-hoc signed. The ZIP is a local, unsigned-by-Developer-ID build,
not a notarized public release. A downloaded public release still needs Developer
ID signing and notarization using the owner's Apple developer credentials.

Tests use temporary shell files and a simulated defaults backend; they do not
apply your preferences, install software, or edit your shell configuration.

## Source map

| File | Owns |
| --- | --- |
| `Sources/App.swift` | Window, local-file policy, validated action bridge, checklist state |
| `Sources/SetupCore.swift` | Process runner, tools, settings, typed backups, shell setup, disk scan |
| `Sources/SelfTests.swift` | Native regressions using isolated fixtures |
| `Resources/Web/` | Interface and offline original guides |
| `Resources/Config/` | Bundled preferences, shell block, installer and guide catalogs |
| `Tools/import-reference.py` | Explicit reference snapshot refresh; not used by builds |
| `Resources/ArfanReset1.png` | Full-bleed source artwork; `build.sh` turns it into `ArfanReset1.icns` like ArfanMenu3 |

The reference snapshot is from
`vt8/apps/pages1/pages/os/macOS/reset1/` on October 2, 2026. The source checkout is
read-only reference material. Optional Go/Zig versions and checksums preserve that
snapshot; review the guide when targeting another project or version.

To refresh the bundled reference deliberately:

```sh
python3 Tools/import-reference.py /path/to/vt8/apps/pages1/pages/os/macOS/reset1
./build.sh --selftest
```

The native CLT action uses Apple's documented `xcode-select --install` dialog.
The bundled guide preserves the original Software Update script. The native core
needs no Deno or Python to apply the imported preferences or Zsh setup.
Official installer references: [Apple developer tools](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/),
[Deno installation](https://docs.deno.com/runtime/getting_started/installation/),
and [uv installation](https://docs.astral.sh/uv/getting-started/installation/).
