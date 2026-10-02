(async () => {
// Every reset page, in the order the sidebar and the index show them. Pages with a step number
// go under "Fresh Mac, in order"; optional pages and tools have separate groups.
const PAGES = [
  { file: 'install-command-line-tools.html', label: 'Command Line Tools', title: 'Install Command Line Tools', step: 1, about: 'clang, git and make from Software Update. No dialog.' },
  { file: 'install-cli-tools.html', label: 'CLI tools', title: 'Install CLI tools', step: 2, about: 'Deno, uv, Atuin, Claude Code, Codex, Node through nvm, Bun, and OpenCode.' },
  { file: 'install-homebrew.html', label: 'Homebrew', title: 'Install Homebrew', step: 3, about: 'The brew.sh installer, then brew on your PATH.' },
  { file: 'setup-defaults.html', label: 'macOS defaults', title: 'Set macOS defaults', step: 4, about: 'Finder, keyboard, Dock, screenshot and zoom settings in one paste.' },
  { file: 'setup-defaults2.html', label: 'Trackpad & Accessibility', title: 'Trackpad and Accessibility', step: 5, about: 'Mission Control gesture off, zoom gesture on, Accessibility Keyboard on.' },
  { file: 'optional-cli-tools.html', label: 'Optional CLI tools', title: 'Optional CLI tools', group: 'Optional', about: 'Go, Zig 0.16.0, and Rust installers for Apple Silicon.' },
  { file: 'optional-builds.html', label: 'Optional builds', title: 'Optional builds', group: 'Optional', about: 'Build Ghostty with the Zig version its checkout requires.' },
  { file: 'setup-zsh.html', label: 'faster zsh startup', title: 'Faster zsh startup', group: 'Optional', about: 'Back up .zshrc and defer nvm and completions until first use.' },
  { file: 'disk-usage.html', label: 'disk usage (uv)', title: 'Disk usage (uv)', about: 'Scan your home folder with uv and Rich. Read only.' },
  { file: 'disk-usage-macos.html', label: 'disk usage (macOS)', title: 'Disk usage (macOS)', about: 'The same scan with system python3 and a temporary environment. No uv needed.' },
];
const STEPS = PAGES.filter(page => page.step);
const GROUPS = [
  ['Fresh Mac, in order', STEPS],
  ['Optional', PAGES.filter(page => page.group === 'Optional')],
  ['Tools', PAGES.filter(page => !page.step && !page.group)],
];

const here = location.pathname.split('/').pop() || 'index.html';
function build(tag, props, children) {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children);
  return node;
}

// Done marks live in this browser only, keyed by file name.
const KEY = 'reset1:done';
const done = new Set(JSON.parse(localStorage.getItem(KEY) || '[]'));
const save = () => localStorage.setItem(KEY, JSON.stringify([...done]));
const doneCount = () => STEPS.filter(page => done.has(page.file)).length;
const nextStep = () => STEPS.find(page => !done.has(page.file));

function item({ file, label, step }) {
  const link = build('a', { className: 'item', href: file }, [
    build('span', { className: 'dot', textContent: done.has(file) ? '✓' : step ?? '·' }, []), label,
  ]);
  link.classList.toggle('is-done', done.has(file));
  if (file === here) link.setAttribute('aria-current', 'page');
  return build('li', {}, [link]);
}

function renderRail(rail) {
  const count = doneCount();
  const meter = build('div', { className: 'meter', role: 'img', ariaLabel: `${count} of ${STEPS.length} steps done` }, STEPS.map(page => {
    const segment = build('i', { title: `${page.step}. ${page.label}` }, []);
    segment.classList.toggle('on', done.has(page.file));
    segment.classList.toggle('here', page.file === here);
    return segment;
  }));
  rail.replaceChildren(
    build('div', { className: 'head' }, [
      build('a', { className: 'home', href: 'index.html', textContent: 'Reset a Mac' }, []),
      build('span', { className: 'count', textContent: `${count} of ${STEPS.length} done` }, []),
    ]),
    meter,
    build('nav', { ariaLabel: 'Reset pages' }, [
      ...GROUPS.flatMap(([name, pages]) => [
        build('h2', { textContent: name }, []),
        build('ol', {}, pages.map(item)),
      ]),
    ]),
  );
}

function renderCards(root) {
  const card = ({ file, title, step, about }) => {
    const link = build('a', { href: file }, [
      build('span', { className: 'dot', textContent: done.has(file) ? '✓' : step ?? '·' }, []),
      build('span', {}, [build('strong', { textContent: title }, []), build('span', { className: 'd', textContent: about }, [])]),
      build('span', { className: 'go', textContent: '→' }, []),
    ]);
    link.classList.toggle('is-done', done.has(file));
    return build('li', {}, [link]);
  };
  const next = nextStep();
  const banner = next
    ? build('div', { className: 'continue' }, [
      build('p', {}, [build('small', { textContent: doneCount() ? `${doneCount()} of ${STEPS.length} done. Next up:` : 'Start here:' }, []), build('strong', { textContent: `Step ${next.step}: ${next.title}` }, [])]),
      build('a', { className: 'btn', href: next.file, textContent: doneCount() ? 'Continue →' : 'Start →' }, []),
    ])
    : build('div', { className: 'continue' }, [
      build('p', {}, [build('small', { textContent: `All ${STEPS.length} steps done.` }, []), build('strong', { textContent: 'This Mac is set up.' }, [])]),
      build('button', { className: 'btn', type: 'button', textContent: 'Clear marks', onclick: () => { done.clear(); save(); location.reload(); } }, []),
    ]);
  root.replaceChildren(banner, ...GROUPS.flatMap(([name, pages]) => [
    build('h2', { className: 'group', textContent: name }, []),
    build('ul', { className: 'cards' }, pages.map(card)),
  ]));
}

// Step pages end with a bar: tick it when the step worked, then go to the next one.
function renderFinish(main) {
  const page = PAGES.find(p => p.file === here);
  if (!page?.step) return;
  const next = STEPS.find(p => p.step === page.step + 1);
  const box = build('input', { type: 'checkbox', checked: done.has(here) }, []);
  const bar = build('div', { className: 'finish' }, [
    build('label', {}, [box, `Step ${page.step} worked on this Mac`]),
    build('span', { className: 'spacer' }, []),
    next
      ? build('a', { className: 'btn primary', href: next.file, textContent: `Next: ${next.label} →` }, [])
      : build('a', { className: 'btn primary', href: 'index.html', textContent: 'Back to all steps' }, []),
  ]);
  const sync = () => bar.classList.toggle('is-done', box.checked);
  box.addEventListener('change', () => {
    if (box.checked) done.add(here); else done.delete(here);
    save(); sync();
    for (const rail of document.querySelectorAll('.rail')) renderRail(rail);
  });
  sync();
  const footer = main.querySelector('footer');
  if (footer) footer.before(bar); else main.append(bar);
}

// Copy rebuilds the text from the lines, so the line numbers and "$" prompts never come along.
const text = code => [...code.querySelectorAll('.l')].map(line => line.textContent).join('\n');
async function copy(value) {
  try { await navigator.clipboard.writeText(value); return true; } catch {
    const area = Object.assign(document.createElement('textarea'), { value });
    area.style.cssText = 'position:fixed;opacity:0'; document.body.append(area); area.select();
    const ok = document.execCommand('copy'); area.remove(); return ok;
  }
}

// highlight.js colours every line except the heredoc's opening and closing lines (marked `.h`).
// A token can span lines (a doc comment), so each line closes its open spans and the next reopens
// them. In a `.one` block the first word of a line is marked as a command, which highlight.js
// misses for paths like /bin/bash. Without the library the page keeps its plain version.
function highlight(code) {
  const body = [...code.querySelectorAll('.l:not(.h)')];
  const { value } = hljs.highlight(body.map(line => line.textContent).join('\n'), { language: code.dataset.lang, ignoreIllegals: true });
  const open = [], lines = [];
  let line = '';
  for (const part of value.split(/(<span[^>]*>|<\/span>|\n)/)) {
    if (part === '\n') { lines.push(line + '</span>'.repeat(open.length)); line = open.join(''); continue; }
    if (part.startsWith('<span')) open.push(part);
    else if (part === '</span>') open.pop();
    line += part;
  }
  lines.push(line + '</span>'.repeat(open.length));
  const shell = code.closest('.one');
  body.forEach((element, index) => {
    element.className = 'l';
    element.innerHTML = shell ? lines[index].replace(/^([\w./-]+)(?=\s|$)/, '<span class="hljs-built_in">$1</span>') : lines[index];
  });
}

// A block with data-src holds the runner lines; insert the script before its closing marker.
// data-script-end marks the Python closer when an outer shell heredoc follows it.
async function load(code) {
  const response = await fetch(code.dataset.src, { cache: 'no-store' });
  if (!response.ok) throw new Error(`${code.dataset.src}: ${response.status}`);
  // Val Town may prepend a source-link comment before a script's shebang.
  // A heredoc already selects its interpreter, so omit shebang lines anywhere
  // in the fetched source, including after that hosting preamble.
  const lines = (await response.text()).replace(/^\uFEFF?#![^\n]*(?:\n|$)/gm, '').replace(/\n$/, '').split('\n');
  const end = code.querySelector('[data-script-end]') || code.lastElementChild;
  end.before(...lines.map(line => build('span', { className: 'l', textContent: line }, [])));
  const meta = code.closest('.panel')?.querySelector('.bar .meta');
  if (meta) meta.textContent = `${code.querySelectorAll('.l').length} lines`;
}

function fold(pre) {
  const count = pre.querySelectorAll('.l').length;
  if (count <= 12) return;
  const panel = pre.closest('.panel');
  const toggle = build('button', { className: 'fold', type: 'button' }, []);
  const set = folded => {
    panel.classList.toggle('folded', folded);
    toggle.textContent = folded ? `Show all ${count} lines` : 'Fold script';
    toggle.setAttribute('aria-expanded', String(!folded));
  };
  toggle.addEventListener('click', () => set(!panel.classList.contains('folded')));
  pre.after(toggle);
  set(true);
}

for (const rail of document.querySelectorAll('.rail')) renderRail(rail);
for (const root of document.querySelectorAll('[data-cards]')) renderCards(root);
renderFinish(document.querySelector('main'));

if (window.hljs) for (const code of document.querySelectorAll('code[data-lang]')) highlight(code);
for (const pre of document.querySelectorAll('pre.tall')) fold(pre);

for (const button of document.querySelectorAll('[data-copy]')) {
  const label = button.querySelector('span'), idle = label.textContent;
  button.addEventListener('click', async () => {
    const ok = await copy(text(document.getElementById(button.dataset.copy)));
    label.textContent = ok ? 'Copied. Paste in Terminal' : 'Copy failed';
    button.classList.toggle('done', ok);
    clearTimeout(button.timer);
    button.timer = setTimeout(() => { label.textContent = idle; button.classList.remove('done'); }, 1800);
  });
}

// A segmented control swaps the text of one line, e.g. the run command's flags.
for (const group of document.querySelectorAll('[data-mode]')) {
  const line = document.getElementById(group.dataset.mode);
  for (const option of group.querySelectorAll('button')) option.addEventListener('click', () => {
    for (const other of group.querySelectorAll('button')) other.setAttribute('aria-pressed', String(other === option));
    line.textContent = option.dataset.line;
  });
}

})();
