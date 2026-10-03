# Later: make preference Undo survive repeated Apply

**Status: deferred by request.** The current work does not change preference backup selection.

## Problem to reproduce

1. Apply a preference that changes its value.
2. Apply the same selection again without changing anything.
3. Choose **Restore last preference backup**.

The second Apply replaces `preferences-latest.json` with the already-applied values.
Restore therefore does not return to the value from before the first Apply.
Timestamped backups still exist in `~/Library/Application Support/ArfanReset1/`.

## Implement later

- [ ] Leave the latest useful backup unchanged when Apply has nothing to change.
- [ ] Add a dated preference-backup picker with a preview of affected keys.
- [ ] Clearly identify the selected run before restoring it.
- [ ] Add fixture tests for repeated Apply, mixed changed/unchanged selections, and restore.

## Start here

Read `SetupEngine.apply` and `SetupEngine.restore` in [SetupCore.swift](Sources/SetupCore.swift).
The recovery controls are in [app.js](Resources/Web/app.js).
Use simulated preference writes; do not change real Mac preferences as a test.
