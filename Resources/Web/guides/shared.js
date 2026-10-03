(async () => {
function build(tag, props, children) {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children);
  return node;
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

// A block with data-src holds the runner lines; the script goes before its closing line (the last `.h` line, or
// data-script-end), or makes up the whole block when it has no runner. The files live in Resources/Scripts;
// ArfanReset1 expands their `# @include` lines and hands them over as window.RESET1_SCRIPTS, because a
// file:// page cannot fetch them.
function load(code) {
  const source = (window.RESET1_SCRIPTS || {})[code.dataset.src];
  const lines = (source ?? `# ${code.dataset.src} is missing from the app's Scripts folder.`).split('\n');
  const runner = code.querySelectorAll('.l.h');
  const end = code.querySelector('[data-script-end]') || (runner.length > 1 ? runner[runner.length - 1] : null);
  const spans = lines.map(line => build('span', { className: 'l', textContent: line }, []));
  if (end) end.before(...spans); else code.append(...spans);
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

for (const code of document.querySelectorAll('code[data-src]')) load(code);
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
