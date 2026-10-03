# Changelog

Newest first. Each heading under Unreleased is one batch of work.

## Unreleased

### Appearance and icon style choices

- macOS defaults has two choice rows in the Appearance group. **Appearance** offers Light, Dark or Auto. **Icon & widget style** offers Default, Dark, Clear or Tinted, each with its light, dark or auto variant. Dark is the default for both.
- A choice row has a menu instead of one fixed value. After a check it names the option this Mac uses now.
- Choices live in `Resources/Config/choices.json`, which the importer never rewrites. A choice replaces the imported row for the same key, so the old automatic-appearance row is gone.
- The engine can now remove a key, which is how macOS stores Light appearance and the Default icon style.
- Recognize both missing-key messages from `defaults`, including the newer “Could not find key” wording, so an absent automatic-appearance key is not reported as a failure.
- Added web-template coverage for choice defaults, options, current values, row selection and disabled controls.

### Interface repair and plain-language pass

- Pages added after the Drafting Paper redesign follow it again. Card titles, spacing, link buttons, the filter select and the guides' Start here box now use the system's components and tokens.
- Preference pages show their three steps (Check, Choose, Apply) as a strip with each button inside its step. After a check, the strip counts the rows that would change, are already set or failed.
- Preference rows show the proposed value. A row that would change, or failed, also shows the current value. The filter labels match the row badges.
- Tool cards are shorter: a status badge beside the name, the detected version and path in one block, Website and Docs as quiet links.
- The highlighted button is the next action. On Command Line Tools, Homebrew and Google Chrome it starts on Check installation and moves to the installer only once a check finds nothing.
- Reading & typing lists each setting's four ways as rows, with permissions and scripts folded underneath.
- Zsh and function previews tint added and removed lines.
- Every setup step ends with a button to the next step.
- Renamed: Run in Terminal is Install in Terminal, Check this Mac is Check all tools, Add/update function is Add to .zshrc, and Select visible is Select shown.
- Removed the extra Check this Mac button from the Command Line Tools, Homebrew and zsh pages. Each already has its own check or preview.
- Run-log entries for tool checks use the page's own marks and words: ✓ Detected, • Not found, ✕ Check failed.
- Rewrote the page text, guide intros, README and AGENTS.md so each leads with the action.

### Google Chrome page

- New Apps page for Chrome, with Google's download and a Homebrew install (`brew install --cask google-chrome`). The script names the Homebrew step when `brew` is missing.
- Check installation reads the version from `/Applications` or `~/Applications` without opening Chrome.

### Reading & typing page

- New Accessibility page for Speak selection and the Accessibility Keyboard. Each can be turned on in System Settings, by a bundled AppleScript in Terminal, through a prepared Codex chat, or through the Codex CLI.
- The AppleScript finds the switch by its exact identifier, clicks once only if it is off, and verifies the result. The app never claims to have verified the switch itself.

### Shell functions

- Add a catalog-driven Shell functions page with the supplied killport and repos definitions.
- Support Copy, read-only diff preview and backed-up installation into the selected .zshrc.
- Show missing dependency files and reject conflicting unmanaged definitions.

### CLI tool cards

- Remove CLI and Optional CLI reference guides.
- Separate nvm installation from Node.js 26; omit the explicit nvm.sh sourcing line.
- Add Website and Docs links to CLI tool cards, plus independent nvm detection.

### Check results and recovery

- Show current and proposed preferences with result filters and session check times.
- Preserve partial preference-run logs on failure or cancellation.
- Distinguish unknown permissions from confirmed access.
- Preview Zsh changes and restore a selected backup with a safety copy.
- Show version and path checks on installer cards.
- Shorten task text and add action-first entry points to offline guides.
- Record deferred preference backup selection in TODO.md.

### Step order and accessibility settings

- **faster zsh startup** is now step 4, before the preference steps (macOS defaults is 5, Accessibility & gestures is 6). Its original guide and the scripts only it used (`setup-zsh.py`, `zsh-report.py`, `zsh-completions.zsh`) are removed. The page lists the files the step changes, live from disk, with Show in Finder and Open (TextEdit) buttons.
- What was then step 5 (step 6 now) became **Accessibility & gestures**, grouped as Mission Control, Zoom and Accessibility Keyboard. The Zoom and Dwell preferences moved there from macOS defaults, so every protected preference and its Full Disk Access note sit on one page. Preference IDs are unchanged, so saved selections carry over.

### Editable scripts and split Disk usage

- Scripts moved out of the guide HTML into `Resources/Scripts/` as plain files, with shared output style in `lib/style.sh` (bash/zsh) and `lib/style.py` (uv + Rich). `# @include lib/…` lines are expanded when the app loads a script, so copied and Terminal-run scripts stay self-contained. Guides receive the scripts from the app; `--script <name>` prints one expanded.
- Scripted installers (Command Line Tools, Homebrew, Node, Go, Zig) run their script file; the Go, Zig, Homebrew and Ghostty scripts now use the shared style.
- Removed the two Rich disk-usage guides; the native Disk usage page replaces them. The importer now refreshes only preferences and the Zsh block.
- Disk usage lists folders and files in two tables by default (switch: Folders and files apart), each with its size, share and count; the legend and header show percentages too. Scans keep the top 60 of each kind; older saved scans still open.

### Permissions, sounds and the Command Line Tools installer

- Permissions page under Overview: read-only checks for Full Disk Access, administrator account, Terminal, `.zshrc` write access and the app data folder, each with the steps that use it and a System Settings shortcut. The sidebar and Overview flag anything not allowed.
- Command Line Tools runs the Software Update script in Terminal instead of linking the original guide; `xcode-select --install` is the alternative, with links to Xcode on the App Store and Apple's downloads.
- The run log has a Collapse/Expand button next to Copy log; collapsed, it shows the log's first line. The choice is remembered.
- Interface sounds from Drafting Paper (Web Audio, no files): taps, pitched page selects, switch on/off, a destructive Stop, a chime or error pulse when an action finishes, a bell for notices. Sounds switch in the sidebar.

### Drafting Paper redesign and native Disk usage

- Redesigned the interface on the Drafting Paper system: paper-and-ink tokens, serif titles, one indigo accent, light and dark themes.
- Removed the titlebar like ArfanView1: transparent, no title, page runs under the traffic lights, window still drags from the top edge.
- Initial window is now 1200×860 at top-left 100,80 (was 900×1100 at 100,100).
- App icon is the supplied ArfanReset1 artwork, full-bleed, built with ArfanMenu3's sips/tiffutil/tiff2icns pipeline and named `ArfanReset1.icns`.
- The run log can be resized by dragging or with the arrow keys on its top edge; the height is remembered.
- Disk usage saves each folder's scan (in Application Support, owner-only) so reopening a folder, going back, or relaunching the app does not rescan; Refresh rescans the folder you are viewing, and the page shows when it was scanned.
- Disk usage is a native view: volume bar, folder breakdown with sizes, drill-down and Show in Finder. The original Rich-report guides were removed from this page.
- Reference guides use the same palette; fixed their content sitting in an empty sidebar column.

## 26.10.2

- Initial Swift/AppKit app with a bundled web interface and a six-step setup checklist.
- 86 selectable preferences, read-only checks, typed backups and last-run restore.
- Native Zsh setup and read-only disk usage; reviewed installers in Terminal.
- Ten offline reference guides from the vt8 macOS reset1 pages.
- 900×1100 initial window at top-left 100,100; Apple Silicon and Intel packaging.
