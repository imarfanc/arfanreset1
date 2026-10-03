# ArfanReset1

Rules for working in `macos/arfanreset1/`. For the workflow and the file map,
read [README.md](README.md).

## Before you call a change done

1. Run `./build.sh --selftest`. Keep compilation warning-free.
2. Check UI navigation and changed controls in the actual app when available.
3. Report build and test results separately from live setup verification.

Optional: `node Tools/test-web.cjs` covers the web templates.

## Architecture

- Keep the Swift/AppKit + bundled WKWebView architecture.
- No server, external web assets, package manager, or Python/Deno runtime
  requirement for native setup actions.
- Reference vt8 files are read only.

## Bridge and installers

- The bridge accepts known actions and catalog IDs from the bundled main frame only.
- Never execute command text supplied by the web page.
- Installers use reviewed, bundled commands in Terminal. The page cannot claim
  they completed.

## Anything that changes the Mac

- Checks are read only.
- Back up typed preference values before applying. Restore only touched keys.
- For Zsh, preserve unrelated content, symlinks and permissions, validate with
  `zsh -n`, then replace atomically.
- Do not run real setup actions or installers as validation.
- Native regressions must use isolated fixtures.

## Build and distribution

- For distribution, run `./build.sh --universal --zip`.
- Use `--install` only when installation is requested.

## Window

- Preserve the requested startup frame: 1200×860 logical points at top-left
  100,80 on the main display.
- The titlebar is transparent with a hidden title and full-size content, like
  ArfanView1.
- Keep the invisible `DragStrip` so the window stays draggable.
- Keep interactive page content below the top 28 points.

## Interface

- The interface follows Drafting Paper (cf2 `designs1/drafting-paper.html`).
  Tokens are in `app.css`. Dark values come from `prefers-color-scheme`.
- Pages are built from the components already in `app.css`: cards, flow steps
  (`.flow`), tool cards (`.tool`), method lists (`.methods`) and list rows
  (`.item`). Card titles are `h3`. A view has at most one primary button, on
  the next action.
- The icon is `Resources/ArfanReset1.png` (full-bleed), built into
  `ArfanReset1.icns` with sips, tiffutil and tiff2icns, like ArfanMenu3.
