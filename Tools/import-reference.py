#!/usr/bin/env python3
"""Snapshot reset1's settings, shell block, commands and offline guides. Build needs no Python."""
import ast
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1])
config = ROOT / 'Resources/Config'
guides = ROOT / 'Resources/Web/guides'
guides.mkdir(parents=True, exist_ok=True)

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
write('settings.json', settings)

tree = ast.parse((source / 'scripts/setup-zsh.py').read_text())
shell = {}
for node in tree.body:
    if isinstance(node, ast.Assign) and node.targets[0].id in ('START', 'END', 'CONFIG', 'EAGER_LINES'):
        value = ast.literal_eval(node.value)
        shell[node.targets[0].id] = sorted(value) if isinstance(value, set) else value
write('shell.json', shell)

class Commands(HTMLParser):
    def __init__(self):
        super().__init__(); self.id = None; self.line = None; self.lines = []; self.result = {}
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'code' and attrs.get('id'):
            self.id = attrs['id']; self.lines = []
        if tag == 'span' and self.id and 'l' in attrs.get('class', '').split():
            self.line = ''
    def handle_data(self, text):
        if self.line is not None: self.line += text
    def handle_endtag(self, tag):
        if tag == 'span' and self.line is not None:
            self.lines.append(self.line); self.line = None
        if tag == 'code' and self.id:
            self.result[self.id] = '\n'.join(self.lines); self.id = None

commands = []
titles = {'deno':'Deno', 'uv':'uv', 'atuin':'Atuin', 'claude':'Claude Code', 'codex':'Codex CLI', 'node':'Node.js through nvm', 'bun':'Bun', 'opencode':'OpenCode'}
for page in ['install-cli-tools.html', 'install-homebrew.html', 'optional-cli-tools.html']:
    p = Commands(); p.feed((source / page).read_text())
    for key, command in p.result.items():
        if key in ['check', 'path', 'optional-versions']: continue
        name = 'Homebrew' if key == 'install' else titles.get(key, key.replace('-install','').title())
        if key == 'install':
            command += '\nif [[ -x /opt/homebrew/bin/brew ]]; then\n  line=\'eval "$(/opt/homebrew/bin/brew shellenv zsh)"\'\nelif [[ -x /usr/local/bin/brew ]]; then\n  line=\'eval "$(/usr/local/bin/brew shellenv zsh)"\'\nelse\n  exit 1\nfi\ntouch "$HOME/.zprofile"\ngrep -qxF "$line" "$HOME/.zprofile" || print -r -- "$line" >> "$HOME/.zprofile"\neval "$line"'
        commands.append(dict(id=key, name=name, command=command, optional=page == 'optional-cli-tools.html', guide=page))
write('installers.json', commands)

guide_list = []
for path in sorted(source.glob('*.html')):
    if path.name == 'index.html': continue
    content = path.read_text()
    title = html.unescape(re.search(r'<title>(.*?)</title>', content).group(1))
    content = re.sub(r'<link[^>]+https:[^>]+>\n?', '', content)
    content = re.sub(r'<script[^>]+https:[^>]+></script>\n?', '', content)
    def embed(match):
        attrs, script, body = match.groups()
        script_text = (source / script.split('?')[0]).read_text()
        script_text = re.sub(r'^\ufeff?#![^\n]*(?:\n|$)', '', script_text, flags=re.M).rstrip('\n')
        spans = ''.join(f'<span class="l">{html.escape(line)}</span>' for line in script_text.split('\n'))
        closer = re.search(r'<span[^>]*data-script-end[^>]*>', body)
        offset = closer.start() if closer else body.rfind('<span')
        return '<code' + attrs + '>' + body[:offset] + spans + body[offset:] + '</code>'
    content = re.sub(r'<code([^>]*?) data-src="([^"]+)"[^>]*>(.*?)</code>', embed, content, flags=re.S)
    content = re.sub(r'<script type="module" src="shared.js[^\"]*">', '<script src="shared.js">', content)
    content = content.replace('<aside class="rail"></aside>', '')
    content = content.replace('</html>', '<style>main{margin-left:0;max-width:100%;padding:24px} .finish{display:none}</style></html>')
    (guides / path.name).write_text(content)
    guide_list.append(dict(file=path.name, title=title))
shutil.copy2(source / 'shared.css', guides / 'shared.css')
js = (source / 'shared.js').read_text()
# Embedded source scripts eliminate fetch and ES modules over file://.
js = re.sub(r'await Promise\.all\(.*?\n\}\)\)\);', '', js, flags=re.S)
(guides / 'shared.js').write_text('(async () => {\n' + js + '\n})();\n')
write('guides.json', guide_list)
print(f'Imported {len(settings)} preferences, {len(commands)} installers and {len(guide_list)} offline guides.')
