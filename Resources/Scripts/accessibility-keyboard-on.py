#!/usr/bin/env python3
"""Turns on Accessibility → Keyboard → Accessibility Keyboard, with its dwell settings."""
import subprocess
import sys

# @include lib/style.py

CHECK = "--check" in sys.argv
DOMAIN = "com.apple.universalaccess"
# Corner keys 0–3; action 1 is Hide / Show Home Panel, 0 is none. Only bottom-right gets it.
CORNERS = {"0": 0, "1": 1, "2": 0, "3": 0}
SETTINGS = [
    ("Accessibility Keyboard", "virtualKeyboardOnOff", ["-bool", "true"]),
    ("Default dwell time", "dwellTimeDefaultAction", ["-float", "0.25"]),
    ("Dwell corners", "virtualKeyboardCornerActionType",
     ["-dict", *[a for k, v in CORNERS.items() for a in (k, "-int", str(v))]]),
]


def defaults(*args: str) -> str | None:
    done = subprocess.run(["defaults", *args], capture_output=True, text=True)
    return done.stdout.strip() if done.returncode == 0 else None


def show(value: str | None) -> str:
    if value is None:
        return "unset"
    return {"1": "on", "0": "off"}.get(value, " ".join(value.split()))


heading("Accessibility · Accessibility Keyboard")

# System Settings caches the pane, so it has to quit to show the new value.
if not CHECK:
    subprocess.run(["osascript", "-e", 'quit app "System Settings"'], capture_output=True)
    info("Quit System Settings so it rereads the setting.")

table = make_table("Setting", "Before", "After")
failed = False
for label, key, value in SETTINGS:
    was = defaults("read", DOMAIN, key)
    if not CHECK and defaults("write", DOMAIN, key, *value) is None:
        failed = True
    table.add_row(label, f"[dim]{show(was)}[/]", f"[bold]{show(defaults('read', DOMAIN, key))}[/]")
console.print(table)

if CHECK:
    info("--check: nothing was written.")
elif failed:
    panel(
        "macOS refused the write. Accessibility settings live in a protected domain that only a "
        "Terminal with Full Disk Access can change.\n\n"
        "System Settings → Privacy & Security → Full Disk Access → turn on your Terminal app, "
        "quit and reopen it, then paste this again.\n\n"
        "Or set it by hand: System Settings → Accessibility → Keyboard → Accessibility Keyboard.",
        "Needs Full Disk Access", "warn",
    )
    sys.exit(1)
else:
    # The preference alone does not show the keyboard until its app runs.
    subprocess.run(["open", "-a", "/System/Library/CoreServices/AssistiveControl.app"], capture_output=True)
    ok("On. Dwell on the bottom-right corner for 0.25 s to hide or show the Home Panel.")
