#!/usr/bin/env python3
"""Snapshot reset1's preference catalog and Zsh setup block. Build needs no Python."""
import ast
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1])
config = ROOT / 'Resources/Config'

def write(name, value):
    (config / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')

settings = []
text = (source / 'scripts/setup-defaults.ts').read_text()
for line in text.splitlines():
    if not line.strip().startswith('{ group:'):
        continue
    line = line.strip().rstrip(',').replace('SCREENSHOT_DIR', '"~/Desktop/screenshots"')
    line = re.sub(r'(\w+): ', r'"\1": ', line)
    data = json.loads(line)
    data['id'] = f"default-{len(settings)}"
    data['section'] = 'defaults'
    settings.append(data)
for domain in ('com.apple.AppleMultitouchTrackpad', 'com.apple.driver.AppleBluetoothMultitouch.trackpad', 'NSGlobalDomain'):
    for fingers in ('Three', 'Four'):
        key = f'Trackpad{fingers}FingerVertSwipeGesture' if domain != 'NSGlobalDomain' else f'com.apple.trackpad.{fingers.lower()}FingerVertSwipeGesture'
        settings.append(dict(id=f'gesture-{len(settings)}', section='gestures', group='Mission Control', domain=domain, key=key, type='int', value='0', description=f'{fingers}-finger Mission Control swipe off · {domain}', currentHost=domain == 'NSGlobalDomain'))
for key, kind, value, description in [
    ('closeViewTrackpadGestureZoomEnabled', 'bool', 'true', 'Use trackpad gesture to zoom'),
    ('virtualKeyboardOnOff', 'bool', 'true', 'Turn on Accessibility Keyboard'),
]:
    settings.append(dict(id=f'gesture-{len(settings)}', section='gestures', group='Accessibility', domain='com.apple.universalaccess', key=key, type=kind, value=value, description=description))
# Every protected Accessibility preference lives on step 5 with the gestures, grouped by feature. IDs stay as
# imported, so selections saved by an earlier version still apply.
MOVE = {'Zoom': 'Zoom', 'Dwell': 'Accessibility Keyboard'}
REGROUP = {'closeViewTrackpadGestureZoomEnabled': 'Zoom', 'virtualKeyboardOnOff': 'Accessibility Keyboard'}
ORDER = ['Mission Control', 'Zoom', 'Accessibility Keyboard']
for item in settings:
    if item['section'] == 'defaults' and item['group'] in MOVE:
        item['section'], item['group'] = 'gestures', MOVE[item['group']]
    item['group'] = REGROUP.get(item['key'], item['group'])
# The page lists groups in file order; each group opens with its on/off switch, then its options.
settings = [s for s in settings if s['section'] == 'defaults'] + sorted(
    (s for s in settings if s['section'] == 'gestures'), key=lambda s: (ORDER.index(s['group']), not s['id'].startswith('gesture')))
write('settings.json', settings)

tree = ast.parse((source / 'scripts/setup-zsh.py').read_text())
shell = {}
for node in tree.body:
    if isinstance(node, ast.Assign) and node.targets[0].id in ('START', 'END', 'CONFIG', 'EAGER_LINES'):
        value = ast.literal_eval(node.value)
        shell[node.targets[0].id] = sorted(value) if isinstance(value, set) else value
write('shell.json', shell)

# Guides, installers and scripts are no longer imported: their scripts are edited here, in Resources/Scripts,
# and a fresh import would overwrite those edits. Compare against the vt8 pages by hand when they change.
print(f'Imported {len(settings)} preferences and the Zsh setup block. Guides, installers and scripts were left alone.')
