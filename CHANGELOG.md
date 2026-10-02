# Changelog

## Unreleased

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
