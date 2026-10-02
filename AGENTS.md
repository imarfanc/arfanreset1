# ArfanReset1

Keep the Swift/AppKit + bundled WKWebView architecture. No server, external web
assets, package manager, or Python/Deno runtime requirement for native setup actions.
Read README.md for the workflow and file map. Reference vt8 files are read only.

The bridge accepts known actions and catalog IDs from the bundled main frame only.
Never execute command text supplied by the web page. Installers use reviewed,
bundled commands in Terminal; the page cannot claim they completed.

Checks are read only. Back up typed preference values before applying; restore
only touched keys. Preserve unrelated Zsh content, symlinks and permissions,
validate with zsh -n, then replace atomically. Do not run real setup actions or
installers as validation. Native regressions must use isolated fixtures.

Run `./build.sh --selftest`; for distribution, `./build.sh --universal --zip`.
Keep compilation warning-free. Check UI navigation and changed controls in the
actual app when available. Separate build/test results from live setup verification.
Use `--install` only when installation is requested. Preserve the requested startup
frame: 1200×860 logical points at top-left 100,80 on the main display. The titlebar is
transparent with a hidden title and full-size content, like ArfanView1; keep the
invisible `DragStrip` so the window stays draggable, and keep interactive page content
below the top 28 points.
The interface follows Drafting Paper (cf2 `designs1/drafting-paper.html`): tokens in
`app.css`, dark values via `prefers-color-scheme`. The icon is
`Resources/ArfanReset1.png` (full-bleed), built into `ArfanReset1.icns` with sips, tiffutil and tiff2icns like ArfanMenu3.
