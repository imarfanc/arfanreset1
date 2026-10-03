# ArfanReset1

A small native macOS app for the first things to do on a new Mac, or after a reset.
It checks permissions, installs developer tools, speeds up zsh startup and applies
your preferences, one step at a time. Checks never change anything, and every
change is backed up first.

Needs macOS 14 or newer. The built app needs nothing else: no server, package
manager or runtime.

## Start here

Run these from this folder (`macos/arfanreset1/`).

1. Build the app. This needs only Apple's Command Line Tools.

   ```sh
   ./build.sh
   ```

   Expected last line: `Built: <path>/build/ArfanReset1.app`

2. Open it.

   ```sh
   open build/ArfanReset1.app
   ```

3. In the app, open **Permissions** and fix anything marked **Needs attention**.
4. Open **Overview**, choose **Open step 1**, and work through the six steps.
   Tick each step off when you have checked its result.

Using a downloaded copy instead? Unzip it, drag `ArfanReset1.app` into
Applications, and start at step 3.

## Find your task

| I want to | Go to |
| --- | --- |
| See what macOS allows the app | [Permissions](#permissions) |
| Install Git, clang, Homebrew or CLI tools | [Installers](#installers) |
| Change Finder, Dock, keyboard or accessibility settings | [Preferences](#preferences-steps-5-and-6) |
| Speed up zsh, or undo that | [Zsh setup](#zsh-setup-step-4) |
| Install Chrome, turn on Speak selection, add `killport` | [Extra pages](#extra-pages) |
| Find a backup or a log | [Where things are saved](#where-things-are-saved) |
| Build, test or package the app | [Build, test and package](#build-test-and-package) |
| Edit a bundled script | [Scripts](#scripts) |
| Find the file that owns a feature | [Source map](#source-map) |

## The six setup steps

Do them in order. Each page ends with a box to tick and a button to the next step.

| Step | Page | What it does |
| --- | --- | --- |
| 1 | Command Line Tools | Installs Git, clang and make with a bundled Software Update script in Terminal. `xcode-select --install` is the alternative. Links to Xcode are on the same page. |
| 2 | CLI tools | Installs what you pick: Deno, uv, Atuin, Claude Code, Codex CLI, nvm, Node.js, Bun and OpenCode. |
| 3 | Homebrew | Installs Homebrew and adds `brew` to your shell PATH. |
| 4 | faster zsh startup | Backs up `.zshrc`, then loads nvm and completions on first use instead of at every startup. |
| 5 | macOS defaults | Checks and applies the Finder, Dock, keyboard, screenshot and other preferences you select. |
| 6 | Accessibility & gestures | Mission Control swipe off, Zoom (trackpad gesture, shortcuts, modifier scroll) and the Accessibility Keyboard with its dwell settings. |

Checklist marks are manual. The app saves them, but it never ticks a step for you.

## How each kind of action behaves

### Permissions

**Permissions** checks five things: Full Disk Access, an administrator account,
Terminal, writing your `.zshrc`, and the app's own data folder. Each row names
the steps that use it. The check only reads. It changes nothing and shows no
macOS prompt.

The Zoom and Accessibility Keyboard preferences in step 6 need Full Disk Access.
Step 5 does not. After you turn Full Disk Access on, quit and reopen the app.

### Installers

1. Choose **Check installation** on a card, or **Check all tools** for every card.
   The card shows the detected version and path.
2. If the tool is missing, choose **Install in Terminal**. The installer runs
   there so you can answer its prompts and type your password.
3. Choose **Check installation** again.

Good to know:

- **Review installer command** shows exactly what Terminal will run.
- Opening Terminal does not mean the install worked. Only a check confirms it.
- Check results last for this app session. They do not tick a checklist step.
- Install nvm before Node.js. The Node.js card starts a fresh interactive login
  shell and runs `nvm install 26`. It does not source `nvm.sh` itself.
- CLI cards link to each tool's website and docs.

### Preferences (steps 5 and 6)

Each page shows the same three steps.

1. **Check current values.** Reads every preference on the page. Nothing is written.
2. Select the rows you want. Every row shows the proposed value and its last
   result. A row that would change, or that failed, also shows the current value.
3. **Apply N selected.** The app backs up the exact, typed values, writes each
   selected row, then reads it back.

Good to know:

- Apply uses every selected row on the page, including rows a filter has hidden.
- **Show** filters rows by result: Would change, Failed, Already set or Not checked.
- **Appearance** and **Icon & widget style** are choice rows. Pick an option in the row's
  menu, then select the row. Dark is the default for both. They take full effect
  after you log out and back in. Choice rows live in `Resources/Config/choices.json`,
  which the importer never rewrites.
- **Restore last preference backup** puts back only the keys from your last
  Apply. It also removes keys that did not exist before.
- Every Apply also keeps a timestamped backup.
- Finder and the Dock restart only when you choose **Restart Finder & Dock**.
- Some preferences need a logout. Some are ignored by particular macOS releases.
  Read-back confirms the value was saved, not that macOS acts on it.
- If a run is interrupted, the run log keeps the partial results and the backup path.
- Step 6 rows for Zoom and the Accessibility Keyboard start unselected. If macOS
  refuses them, set them in System Settings, or give ArfanReset1 Full Disk
  Access, then quit and reopen the app. Reopen System Settings to refresh its
  cached values.

One known gap is that applying the same selection twice replaces the latest
backup. See [TODO.md](TODO.md).

### Zsh setup (step 4)

1. **Preview changes** shows a before and after diff. Nothing is written.
2. **Set up Zsh** backs up `.zshrc`, then rewrites one marked block in it.
3. Open a new Terminal.

Good to know:

- Setup keeps unrelated lines, symlinks, permissions, custom frameworks, plugins
  and multi-line loader blocks. It checks syntax with `zsh -n` and replaces the
  file atomically.
- **Choose shell folder** points the app at `HOME` or a folder you use for `ZDOTDIR`.
- **Files this step changes** lists the `.zshrc` (and its target, if it is a
  symlink), the `backups` folder and zsh's completion cache, live from disk. You
  can show each in Finder or open it in TextEdit.
- The exact backup path is in the run log.
- To undo, choose **Restore Zsh backup**. It opens a picker in the `backups`
  folder, checks the backup's syntax, and saves your current file before restoring.

## Extra pages

### Google Chrome

Open **Apps → Google Chrome**.

1. Choose **Check installation**. It reads the app's version in `/Applications`
   or `~/Applications` without opening Chrome.
2. If Chrome is missing, install it one of two ways:
   - **Download Chrome from Google** opens Google's download page.
   - **Install with Homebrew** runs `brew install --cask google-chrome` in
     Terminal. If Homebrew is missing, the script says so. Use **Set up
     Homebrew** first.
3. Check installation again.

### Reading & typing

Open **Accessibility → Reading & typing** to turn on Speak selection and the
Accessibility Keyboard. Each setting offers four ways. Pick one.

| Way | What happens |
| --- | --- |
| In System Settings | **Open settings** opens the pane. You turn the switch on yourself. |
| AppleScript in Terminal | **Enable with AppleScript** runs a bundled script. It finds the switch by its exact accessibility identifier, reads it, clicks once only if it is off, then verifies. A missing, ambiguous or unreadable switch stops the script. |
| Codex app | **Open Codex prompt** prepares a new local chat. Choose GPT-6 Luna (`gpt-6-luna`) in the model picker, then send. The prompt asks computer use to enable only that setting and verify it. **Copy prompt** is the fallback. |
| Codex CLI | **Run Codex CLI** opens an interactive Terminal session with `gpt-6-luna`, a workspace-write sandbox and on-request command approvals. It checks that the CLI is installed and signed in, puts the bundled AppleScript in a private temporary task folder, and asks Codex to run it and report the result. The folder path is printed. |

Before you rely on a result:

- The app cannot see the switch. Opening another app does not mark the setting
  on. Read the script's or Codex's last line, and look at the switch.
- Terminal may need Accessibility permission, and Automation access to System
  Events and System Settings. Nothing grants these for you.
- The Codex deep link fills in the prompt. It cannot pick a model or send.
- The Codex CLI way uses your Codex account and may count against your usage.
  It uses AppleScript and Terminal's permissions. It does not assume the desktop
  app's computer-use tools exist in the CLI.
- Older macOS layouts may not expose the same identifiers. If a script cannot
  find its switch, use System Settings.

Sources: [Codex deep links](https://learn.chatgpt.com/docs/reference/commands#deep-links),
[GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna),
[OpenAI CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli).

### Shell functions

Open **Extras → Shell functions** to add `killport` and `repos` to your `.zshrc`.
They need uv and the Python scripts in `~/developer/github/t1/scripts/`. The page
reports missing scripts. The app only adds definitions. It never runs them.

1. Choose **Preview changes** on a function's card.
2. Choose **Add to .zshrc**. The app saves a marked block for that function.
3. Open a new Terminal, then try `killport <port>` or `repos --help`.

Good to know:

- Writes keep unrelated content, symlinks and permissions, check syntax and save
  a backup first.
- An identical definition that is already there is left alone. Nothing is added twice.
- A different definition outside the app's marked blocks needs your review. The
  app does not overwrite it.
- **Restore Zsh backup** restores the whole file, not one function.

To add another function to the app:

1. Put its exact definition in `Resources/Functions/<name>.zsh`.
2. Add an entry to `Resources/Config/functions.json` with `id`, `name`,
   `description`, `usage`, `source` and `requirements` (required file paths).
3. Run `./build.sh --selftest` and reopen the built app.

Use a unique, stable ID, and a function name made of letters, digits or
underscores. The file must end in `.zsh`. A new entry gets its own card, its
Copy, Preview and Add controls, and its own marked block.

### Optional CLI tools, Disk usage and Reference guides

- **Optional CLI tools** has Go, Zig and Rust installers. Go and Zig are pinned
  Apple silicon versions with checksums. Review the scripts before you target
  another version.
- **Disk usage** is a read-only scan of your home folder. A folder you have
  already scanned opens at once. **Refresh** rescans the folder you are viewing.
  **Folders and files apart** (on by default) lists them in two tables, each
  with its total and share. Turn it off for one list by size. Sizes show their
  share of the folder, and the volume legend shows each share of the disk.
- **Reference guides** holds five offline guides from the original instructions.

## The window, run log and sounds

- The window opens at 1200 × 860 logical points, with its top-left corner 100
  points from the left and 80 from the top of the main screen. It keeps that
  frame even on a smaller display. Resize or zoom it if it runs off your screen.
- The run log shows what the last action did. **Collapse** shrinks it to one
  line, and the choice is remembered. A failed action opens it again.
- Sounds are synthesized with Web Audio, so there are no audio files. They play
  only in response to something you did: taps, page selects, switches, and a
  chime when an action finishes. Turn them off with **Sounds** in the sidebar.

## Where things are saved

| What | Where |
| --- | --- |
| Checklist, selected preferences, shell folder | UserDefaults for `com.arfan.arfanreset1` |
| Preference backups, Terminal scripts, last run log | `~/Library/Application Support/ArfanReset1/` |
| Saved Disk usage scans | `disk-cache.json` in that folder, readable only by you |
| Zsh backups | `backups/` beside the selected `.zshrc` |

## Build, test and package

Only Apple's Command Line Tools are needed. No uv or Deno.

Build for this Mac's architecture:

```sh
./build.sh
```

Build, then run the isolated regression checks. Expect `SELFTEST OK`:

```sh
./build.sh --selftest
```

Build an Apple silicon and Intel ZIP in `dist/`:

```sh
./build.sh --universal --zip
```

Install into `/Applications` and open the app. Run this only when you want it installed:

```sh
./build.sh --install
```

From the repository root, the same four are `deno task build:arfanreset1`,
`test:arfanreset1`, `package:arfanreset1` and `install:arfanreset1`.

Optional web-template regressions. Node is a development dependency only:

```sh
node Tools/test-web.cjs
```

Tests use temporary shell files and a simulated defaults backend. They do not
apply your preferences, install software or edit your shell configuration.

The build is ad-hoc signed. The ZIP is a local build, not a notarized public
release. A public release still needs Developer ID signing and notarization
with the owner's Apple developer credentials.

## Scripts

Every multi-line script is a plain file in `Resources/Scripts/`, so you can edit
it directly. That covers the Software Update, Homebrew, Node.js, Go and Zig
installers, the Ghostty build steps, the Python checks (`check-tools.py` and the
trackpad and Accessibility scripts) and `setup-defaults.ts`. One-line installers
stay in `Resources/Config/installers.json`.

Shared output style lives in `Resources/Scripts/lib/`:

| File | For | Provides |
| --- | --- | --- |
| `style.sh` | bash and zsh | `heading`, `ok`, `todo`, `fail`, `info`, `suggest` |
| `style.py` | `uv run --with rich` scripts | The same words, plus `make_table` and `panel`, on Rich |

A script pulls one in with a line such as `# @include lib/style.sh`. The app
pastes the file in its place (one level, `lib/` only) and drops the shebang. So
whatever a guide shows, Copy copies, or Terminal runs is self-contained. A script
installer is wrapped in the heredoc its interpreter needs: `zsh <<'ZSH'` for
`.zsh`, `bash -e <<'SH'` for `.sh`.

Guides name their script with `data-src`. A `file://` page cannot fetch files, so
the app injects the expanded scripts into guide pages.

To try an edit, rebuild and print the expanded script:

```sh
./build.sh
build/ArfanReset1.app/Contents/MacOS/ArfanReset1 --script install-go.sh
```

`./build.sh --selftest` checks every include, runs `bash -n` or `zsh -n` on each
expanded shell script, and confirms every guide's `data-src` exists.

## Source map

Swift and AppKit host a bundled HTML, CSS and JavaScript interface in WKWebView,
like ArfanView1 and ArfanMenu3.

| File | Owns |
| --- | --- |
| `Sources/App.swift` | Window, local-file policy, validated action bridge, checklist state |
| `Sources/SetupCore.swift` | Process runner, tools, settings, typed backups, shell setup, disk scan |
| `Sources/Review.swift` | Structured checks, Zsh diff and backup restore |
| `Sources/Functions.swift` | Shell function catalog, marked blocks and status |
| `Sources/AccessibilityActions.swift` | Reading & typing settings, Codex prompt and CLI command |
| `Sources/SelfTests.swift`, `ReviewTests.swift`, `FunctionTests.swift` | Native regressions using isolated fixtures |
| `Resources/Web/` | Interface (`index.html`, `app.css`, `app.js`) and offline guides |
| `Resources/Scripts/` | Editable scripts and their shared `lib/style.sh` and `lib/style.py` |
| `Resources/Functions/` | Shell function definitions |
| `Resources/Config/` | Bundled preferences, shell block, installer, function and guide catalogs |
| `Tools/test-web.cjs` | Web template regressions |
| `Tools/import-reference.py` | Explicit refresh of the preference catalog and Zsh block. Builds do not use it. |
| `Resources/ArfanReset1.png` | Full-bleed source artwork. `build.sh` turns it into `ArfanReset1.icns`, like ArfanMenu3. |

The interface follows the Drafting Paper design system. Its tokens are at the
top of `Resources/Web/app.css`.

## Reference snapshot

The reference snapshot is from `vt8/apps/pages1/pages/os/macOS/reset1/` on
October 2, 2026. That checkout is read-only reference material. The optional Go
and Zig versions and checksums come from that snapshot.

The guides and scripts are maintained here now. The importer only refreshes
`settings.json` and `shell.json`, and it never overwrites your script edits:

```sh
python3 Tools/import-reference.py /path/to/vt8/apps/pages1/pages/os/macOS/reset1
./build.sh --selftest
```

The Command Line Tools page runs the Software Update script as a reviewed,
bundled installer (`Resources/Scripts/install-clt.zsh`). Apple's documented
`xcode-select --install` dialog is the alternative. The original guide stays in
Reference guides. The CLI tools and Optional CLI tools guides were removed. The
native core needs no Deno or Python to apply the imported preferences or the Zsh
setup.

Official installer references:
[Apple developer tools](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/),
[Deno installation](https://docs.deno.com/runtime/getting_started/installation/),
[uv installation](https://docs.astral.sh/uv/getting-started/installation/).

## Deferred work

[Preference Undo after repeated Apply](TODO.md) is saved for later.
