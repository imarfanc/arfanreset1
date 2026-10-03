#!/usr/bin/env python3
"""Turns on Accessibility → Zoom → Use trackpad gesture to zoom."""
import subprocess
import sys

# @include lib/style.py

CHECK = "--check" in sys.argv
DOMAIN, KEY = "com.apple.universalaccess", "closeViewTrackpadGestureZoomEnabled"


def defaults(*args: str) -> str | None:
    done = subprocess.run(["defaults", *args], capture_output=True, text=True)
    return done.stdout.strip() if done.returncode == 0 else None


def show(value: str | None) -> str:
    return {"1": "on", "0": "off", None: "unset"}.get(value, value or "")


heading("Accessibility · trackpad gesture to zoom")

# System Settings caches the pane, so it has to quit to show the new value.
if not CHECK:
    subprocess.run(["osascript", "-e", 'quit app "System Settings"'], capture_output=True)
    info("Quit System Settings so it rereads the setting.")

was = defaults("read", DOMAIN, KEY)
wrote = CHECK or defaults("write", DOMAIN, KEY, "-bool", "true") is not None
now = defaults("read", DOMAIN, KEY)

console.print(f"  Use trackpad gesture to zoom: [dim]{show(was)}[/] → [bold]{show(now)}[/]")

if CHECK:
    info("--check: nothing was written.")
elif not wrote:
    panel(
        "macOS refused the write. Zoom settings live in a protected domain that only a Terminal "
        "with Full Disk Access can change.\n\n"
        "System Settings → Privacy & Security → Full Disk Access → turn on your Terminal app, "
        "quit and reopen it, then paste this again.\n\n"
        "Or turn it on by hand: System Settings → Accessibility → Zoom.",
        "Needs Full Disk Access", "warn",
    )
    sys.exit(1)
elif now == "1":
    ok("On. Double-tap three fingers to toggle zoom; double-tap and drag to change it.")
else:
    fail("The value did not stick.")
    sys.exit(1)
