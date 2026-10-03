#!/usr/bin/env python3
"""Turns off the Mission Control swipe on the trackpad, for three and four fingers."""
import subprocess
import sys

# @include lib/style.py

CHECK = "--check" in sys.argv
# The built-in and the Bluetooth trackpad keep separate copies, and System Settings reads a third.
# 0 is off, 2 is on.
SETTINGS = [
    (domain, key, "")
    for domain in ("com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad")
    for key in ("TrackpadThreeFingerVertSwipeGesture", "TrackpadFourFingerVertSwipeGesture")
] + [
    ("NSGlobalDomain", f"com.apple.trackpad.{n}FingerVertSwipeGesture", "-currentHost")
    for n in ("three", "four")
]
WANT = "0"


def defaults(*args: str) -> str | None:
    done = subprocess.run(["defaults", *args], capture_output=True, text=True)
    return done.stdout.strip() if done.returncode == 0 else None


def read(domain: str, key: str, host: str) -> str | None:
    return defaults(*filter(None, [host, "read", domain, key]))


def show(value: str | None) -> str:
    return {"0": "off", "2": "on", None: "unset"}.get(value, value or "")


heading("Trackpad · Mission Control gesture off")

# System Settings caches the pane, so it has to quit to show the new value.
if not CHECK:
    subprocess.run(["osascript", "-e", 'quit app "System Settings"'], capture_output=True)
    info("Quit System Settings so it rereads the setting.")

before = [read(*setting) for setting in SETTINGS]
if not CHECK:
    for domain, key, host in SETTINGS:
        defaults(*filter(None, [host, "write", domain, key, "-int", WANT]))
    subprocess.run(["killall", "Dock"], capture_output=True)
after = [read(*setting) for setting in SETTINGS]

table = make_table()
table.add_column("Where", style="dim")
table.add_column("Gesture")
table.add_column("Was", style="dim")
table.add_column("Now")
table.add_column("")
for (domain, key, host), was, now in zip(SETTINGS, before, after):
    where = {"com.apple.AppleMultitouchTrackpad": "built-in trackpad", "NSGlobalDomain": "System Settings"}.get(domain, "Bluetooth trackpad")
    fingers = "three fingers" if "hree" in key else "four fingers"
    status = "[green]✓ off[/]" if now == WANT else ("[yellow]would change[/]" if CHECK else "[red]✕ still on[/]")
    table.add_row(where, fingers, show(was), show(now), status)
console.print(table)

if CHECK:
    info("--check: nothing was written.")
elif all(now == WANT for now in after):
    ok("Mission Control swipe is off. Reopen System Settings → Trackpad → More Gestures to see it.")
    info("If the pane still shows the old choice, log out and back in.")
else:
    fail("Some values did not stick.")
    sys.exit(1)
