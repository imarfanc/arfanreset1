(() => {
  'use strict';
  // [id, label, mark (step number or icon), group heading shown above it, breadcrumb group]
  const pages = [
    ['overview','Overview','i-layers','','Start'],
    ['clt','Command Line Tools','1','Setup, in order','Setup'],
    ['tools','CLI tools','2','','Setup'],
    ['brew','Homebrew','3','','Setup'],
    ['defaults','macOS defaults','4','','Setup'],
    ['gestures','Trackpad & Accessibility','5','','Setup'],
    ['shell','Faster Zsh startup','6','','Setup'],
    ['optional','Optional CLI tools','i-plus','Extras','Extras'],
    ['disk','Disk usage','i-disk','','Extras'],
    ['guides','Reference guides','i-book','','Extras'],
  ];
  const steps = ['clt','tools','brew','defaults','gestures','shell'];
  const $ = id => document.getElementById(id);
  const escape = text => String(text).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let state = null, page = 'overview', search = '';
  const post = (action, extra = {}) => {
    if (window.webkit?.messageHandlers?.reset1) window.webkit.messageHandlers.reset1.postMessage({action,...extra});
    else notice('This action is available in the native Mac app.');
  };
  const icon = (name, extra = '') => `<svg class="icon ${extra}" aria-hidden="true"><use href="#${name}"/></svg>`;
  function notice(text) { $('toast-text').textContent = text; $('toast').hidden = false; clearTimeout(notice.timer); notice.timer = setTimeout(() => $('toast').hidden = true, 2600); }
  function button(label, action, extra = {}, primary = false, glyph = '') {
    return `<button ${primary ? 'class="primary"' : ''} data-action="${action}" data-extra="${escape(JSON.stringify(extra))}" ${state.busy ? 'disabled' : ''}>${glyph ? icon(glyph) : ''}${escape(label)}</button>`;
  }
  function guideLink(file) { return `<button data-guide="${file}">${icon('i-book')}Read original guide</button>`; }
  function note(html, glyph = 'i-info') { return `<div class="alert">${icon(glyph)}<p>${html}</p></div>`; }
  function title(kicker, heading, description) { return `<p class="eyebrow">${kicker}</p><h1>${heading}</h1><p class="lede">${description}</p>`; }
  function finish(id) { return `<label class="finish"><input type="checkbox" data-complete="${id}" ${state.completed.includes(id) ? 'checked' : ''} ${state.busy ? 'disabled' : ''}><span>I’ve finished this step on this Mac</span></label>`; }
  function renderNav() {
    const mark = (id, n) => state.completed.includes(id) ? icon('i-check') : n.startsWith('i-') ? icon(n) : n;
    $('nav').innerHTML = pages.map(([id,label,n,group]) => `${group ? `<div class="group">${group}</div>` : ''}<button data-page="${id}" ${page === id ? 'aria-current="page"' : ''}><span class="number ${state.completed.includes(id) ? 'done' : ''}">${mark(id, n)}</span>${label}</button>`).join('');
    const done = steps.filter(id => state.completed.includes(id)).length;
    $('progress-label').textContent = `${done} of 6 setup steps done`;
    $('meter').setAttribute('aria-label', `${done} of 6 setup steps done`);
    $('meter').innerHTML = steps.map(id => `<i class="${state.completed.includes(id) ? 'on' : ''}"></i>`).join('');
    const [, label, , , crumb] = pages.find(p => p[0] === page);
    $('breadcrumb').innerHTML = page === 'overview' ? `<b>${label}</b>` : `${crumb}<i>/</i><b>${label}</b>`;
    $('activity').textContent = state.busy ? 'Action running…' : 'Ready';
    $('activity').classList.toggle('running', state.busy);
    $('activity').classList.toggle('badge-success', !state.busy);
    $('cancel').hidden = !state.busy;
    $('log').textContent = state.log;
  }
  function installers(filter) {
    return state.installers.filter(filter).map(item => `<article class="card"><div class="row"><div class="grow"><h3>${escape(item.name)}</h3><small>${item.optional ? 'Optional · version pinned in your source guide' : 'Official installer from your setup guide'}</small></div>${button('Run in Terminal','installer',{id:item.id},false,'i-terminal')}</div><details><summary>Review installer command</summary><pre class="command">${escape(item.command)}</pre></details></article>`).join('');
  }
  function preferences() {
    const all = state.settings.filter(s => s.section === page);
    const shown = all.filter(s => `${s.group} ${s.description} ${s.key}`.toLowerCase().includes(search.toLowerCase()));
    const groups = [...new Set(shown.map(s => s.group))];
    const count = all.filter(s => state.selected.includes(s.id)).length;
    return title(page === 'defaults' ? 'Step 4 · Preferences' : 'Step 5 · Trackpad & Accessibility', pages.find(p => p[0] === page)[1], page === 'defaults' ? 'Your Finder, Dock, keyboard, windows and screenshot preferences. Select what you want, check the current values, then apply.' : 'Disable the Mission Control swipe, enable trackpad zoom, and turn on the Accessibility Keyboard.') +
      `<div class="actions">${button('Check only','check',{section:page},true)}${button(`Apply ${count} selected`,'apply',{section:page})}${button('Restart Finder & Dock','restart')}</div>` +
      note('Apply saves the previous values before writing and verifies each value afterwards. Protected Accessibility settings start unselected; they may need Full Disk Access for <strong>ArfanReset1</strong>. Some changes take effect after logging out.') +
      `<div class="actions">${button('Full Disk Access','settings',{id:'privacy'})}${page === 'gestures' ? button('Zoom settings','settings',{id:'zoom'}) + button('Keyboard settings','settings',{id:'keyboard'}) : ''}${guideLink(page === 'defaults' ? 'setup-defaults.html' : 'setup-defaults2.html')}</div>` +
      `<div class="toolbar"><div class="input-icon">${icon('i-search')}<input type="search" id="search" aria-label="Filter preferences" placeholder="Find a preference…" value="${escape(search)}"></div><button data-selection="all" ${state.busy ? 'disabled' : ''}>Select visible</button><button data-selection="none" ${state.busy ? 'disabled' : ''}>Deselect visible</button><small>${count} of ${all.length} selected</small></div>` +
      (groups.length ? groups.map(group => `<h2>${escape(group)}</h2><div class="settings-group">${shown.filter(s => s.group === group).map(s => `<label class="setting"><input type="checkbox" data-setting="${s.id}" ${state.selected.includes(s.id) ? 'checked' : ''} ${state.busy ? 'disabled' : ''}><span class="text"><strong>${escape(s.description)}${s.domain === 'com.apple.universalaccess' ? '<span class="badge badge-warning">Protected</span>' : ''}</strong><small>${escape(s.domain)} · ${escape(s.key)}${s.currentHost ? ' · this Mac' : ''}</small></span><span class="value">${escape(s.value)}</span></label>`).join('')}</div>`).join('') : `<div class="empty">${icon('i-inbox')}<h4>No matching preferences</h4><p>Nothing in this step matches “${escape(search)}”. Try a shorter word, or clear the search to see all ${all.length}.</p></div>`) +
      `<div class="actions">${state.hasBackup ? button('Restore last preference backup','restore') : ''}${button('Show backups & logs','reveal')}</div>` + finish(page);
  }
  // Sizes are decimal (1 GB = 1,000,000,000 bytes), the way Finder and Storage settings report them.
  function size(n) {
    const units = ['B','KB','MB','GB','TB']; let i = 0;
    while (n >= 1000 && i < units.length - 1) { n /= 1000; i++; }
    return `${i === 0 || n >= 100 ? Math.round(n) : n.toFixed(1)} ${units[i]}`;
  }
  const percent = (part, whole) => whole > 0 ? Math.min(100, part / whole * 100) : 0;
  const share = value => value > 0 && value < 1 ? '<1%' : `${Math.round(value)}%`;
  function ago(seconds) {
    const diff = Math.round(seconds - Date.now() / 1000), abs = Math.abs(diff);
    if (abs < 45) return 'just now';
    const [value, unit] = abs < 3600 ? [Math.round(diff / 60), 'minute'] : abs < 86400 ? [Math.round(diff / 3600), 'hour'] : [Math.round(diff / 86400), 'day'];
    return new Intl.RelativeTimeFormat('en', { numeric: 'auto' }).format(value, unit);
  }
  function diskCrumbs(d) {
    const rel = d.path === d.home ? [] : d.path.slice(d.home.length + 1).split('/');
    const trail = [{ label: 'Home', path: d.home }];
    rel.forEach((part, i) => trail.push({ label: part, path: d.home + '/' + rel.slice(0, i + 1).join('/') }));
    return `<div class="trail" role="navigation" aria-label="Folder path">${trail.map((t, i) => i === trail.length - 1
      ? `<b aria-current="location">${escape(t.label)}</b>`
      : `<button class="ghost sm" data-action="disk" data-extra="${escape(JSON.stringify({path:t.path}))}" ${state.busy ? 'disabled' : ''}>${escape(t.label)}</button><i aria-hidden="true">/</i>`).join('')}</div>`;
  }
  function volumeCard(d) {
    const used = Math.max(0, d.volumeTotal - d.volumeAvailable);
    const here = Math.min(d.bytes, used);
    const name = d.path === d.home ? 'Your home folder' : 'This folder';
    return `<div class="card vol"><div class="row"><div class="grow"><h3>${escape(d.volumeName)}</h3><p>${size(used)} used of ${size(d.volumeTotal)} · ${size(d.volumeAvailable)} available</p></div><span class="badge ${percent(used, d.volumeTotal) > 90 ? 'badge-warning' : 'badge-plain'}">${Math.round(percent(used, d.volumeTotal))}% full</span></div>` +
      `<div class="stack" role="img" aria-label="${escape(name)} uses ${size(here)}, other files ${size(used - here)}, ${size(d.volumeAvailable)} available"><i class="here" data-w="${percent(here, d.volumeTotal)}"></i><i class="other" data-w="${percent(used - here, d.volumeTotal)}"></i></div>` +
      `<ul class="legend"><li><i class="sw here"></i>${name} <b>${size(here)}</b></li><li><i class="sw other"></i>Everything else <b>${size(used - here)}</b></li><li><i class="sw free"></i>Available <b>${size(d.volumeAvailable)}</b></li></ul></div>`;
  }
  function diskRows(d) {
    const largest = d.entries.length ? d.entries[0].bytes : 0;
    const rows = d.entries.map(e => {
      const label = e.isDirectory
        ? `<button class="link" data-action="disk" data-extra="${escape(JSON.stringify({path:e.path}))}" ${state.busy ? 'disabled' : ''} title="${(state.diskSaved || []).includes(e.path) ? 'Open the saved scan of' : 'Scan inside'} ${escape(e.name)}">${escape(e.name)}</button>`
        : `<span class="fname">${escape(e.name)}</span>`;
      return `<li class="drow"><span class="dicon">${icon(e.isDirectory ? 'i-folder' : 'i-file')}</span><span class="dname">${label}</span><span class="dbar" aria-hidden="true"><i data-w="${percent(e.bytes, largest)}"></i></span><span class="dsize">${size(e.bytes)}</span><span class="dshare">${share(percent(e.bytes, d.bytes))}</span><button class="sm ghost icon-only" data-action="diskReveal" data-extra="${escape(JSON.stringify({path:e.path}))}" aria-label="Show ${escape(e.name)} in Finder" title="Show in Finder">${icon('i-reveal')}</button></li>`;
    }).join('');
    const more = d.moreCount ? `<li class="drow more"><span class="dicon"></span><span class="dname">${d.moreCount} smaller items</span><span class="dbar"></span><span class="dsize">${size(d.moreBytes)}</span><span class="dshare">${share(percent(d.moreBytes, d.bytes))}</span><span></span></li>` : '';
    return d.entries.length ? `<ul class="dlist">${rows}${more}</ul>` : `<div class="empty">${icon('i-inbox')}<h4>This folder is empty</h4><p>Nothing to measure here. Pick another folder from the path above.</p></div>`;
  }
  function diskPage() {
    const d = state.disk;
    const head = title('Tool · Read only', 'Disk usage', 'See what is taking space in your home folder, then open any folder to look inside. The scan only reads; nothing is deleted or moved.');
    const tools = `<div class="actions">${d ? button('Refresh', 'disk', {path:d.path, refresh:true}, true, 'i-refresh') : button('Scan home folder', 'disk', {}, true, 'i-disk')}${d && d.path !== d.home ? button('Back to home folder', 'disk') : ''}${button('Storage settings','settings',{id:'storage'})}${button('Full Disk Access','settings',{id:'privacy'})}${d ? `<span class="saved" title="${escape(new Date(d.scannedAt * 1000).toLocaleString())}">${icon('i-clock')}Scanned ${ago(d.scannedAt)}</span>` : ''}</div>`;
    if (!d) {
      return head + tools + (state.busy
        ? `<div class="empty"><div class="scanning" aria-hidden="true"><i></i></div><h4>Scanning your home folder…</h4><p>This usually takes a minute or two. You can leave this page; the result will be here when it finishes.</p></div>`
        : `<div class="empty">${icon('i-disk')}<h4>No scan yet</h4><p>Scan your home folder to see which folders take the most space. Protected folders may be skipped unless the app has Full Disk Access.</p></div>`);
    }
    const skipped = d.unreadable > 0 ? note(`${d.unreadable} ${d.unreadable === 1 ? 'item' : 'items'} could not be read, so these totals may be low. Full Disk Access lets the app see more.`, 'i-alert') : '';
    return head + tools + volumeCard(d) + skipped +
      `<div class="card dcard ${state.busy ? 'is-busy' : ''}" aria-busy="${state.busy}">${state.busy ? '<div class="scanning" aria-hidden="true"><i></i></div>' : ''}<div class="dhead">${diskCrumbs(d)}<span class="dtotal"><b>${size(d.bytes)}</b> in ${d.entries.length + d.moreCount} ${d.entries.length + d.moreCount === 1 ? 'item' : 'items'}</span></div>${diskRows(d)}</div>` +
      `<p class="subtle">Scans are saved on this Mac, so a folder you have already opened appears instantly. Use Refresh after you change files. Sizes are space used on disk, in decimal units like Finder, and symbolic links are listed but not followed.</p>`;
  }
  function renderMain() {
    if (!state) return;
    let html = '';
    if (page === 'overview') {
      const next = pages.find(([id]) => steps.includes(id) && !state.completed.includes(id));
      const blurb = {clt:'Apple’s developer tools: Git, clang and make.',tools:'Deno, uv, Atuin, AI tools, Node and Bun.',brew:'Homebrew and its shell PATH.',defaults:'Choose and apply your everyday Mac preferences.',gestures:'Mission Control, zoom and Accessibility Keyboard.',shell:'Back up .zshrc and defer heavy startup work.'};
      html = title('New Mac · after a reset', 'Make this Mac yours.', 'Start with the tools, then your preferences. Everything here is bundled with the app; choose the actions you want to run.') +
        `<p class="subtle">${escape(state.system)}</p>` +
        (next ? `<div class="card next beam"><p class="eyebrow">Next up</p><div class="row"><div class="grow"><h3>${escape(next[1])}</h3><p>${blurb[next[0]]} Go at your own pace; each step has its own actions and guide.</p></div><button class="primary" data-page="${next[0]}">Continue${icon('i-arrow')}</button></div></div>`
               : `<div class="card next"><p class="eyebrow">All done</p><h3>Your checklist is complete</h3><p>You can revisit any step or check the current setup.</p></div>`) +
        `<h2>All six steps</h2><div class="card steps">` +
        steps.map(id => { const [, label, n] = pages.find(p => p[0] === id); const done = state.completed.includes(id); return `<div class="step ${done ? 'done' : ''}"><span class="step-num">${done ? icon('i-check') : n}</span><div class="grow"><strong>${label}</strong><small>${blurb[id]}</small></div><span class="badge ${done ? 'badge-success' : 'badge-plain'}">${done ? 'Done' : 'To do'}</span><button class="sm" data-page="${id}">Open</button></div>`; }).join('') + '</div>' +
        `<div class="actions">${button('Check this Mac','tools',{},true)}${button('Show backups & logs','reveal')}</div><p class="subtle">The app itself needs no uv, Deno, Homebrew, Python or Xcode. Installers use the internet and may ask for your password in Terminal.</p>`;
    } else if (page === 'clt') {
      html = title('Step 1 · Apple developer tools','Command Line Tools','Install Git, clang, make and the macOS SDK through Apple’s installer.') + `<div class="card"><h3>Start with Apple’s installer</h3><p>Open the installation dialog, complete its prompts, then check this Mac. Installing developer tools is optional for the native setup features.</p><div class="actions">${button('Install Command Line Tools','clt',{},true)}${button('Check this Mac','tools')}</div><pre class="command">xcode-select --install</pre></div><div class="card"><h3>Prefer the Software Update script?</h3><p>The original guide includes a Terminal script that finds the newest available package and installs it with sudo.</p>${guideLink('install-command-line-tools.html')}</div>` + finish('clt');
    } else if (page === 'tools' || page === 'optional') {
      html = title(page === 'tools' ? 'Step 2 · Install what you use' : 'Optional · Developer tools', page === 'tools' ? 'CLI tools' : 'Optional CLI tools', 'Review a command, then run its installer in Terminal. Finish any prompts there and return here to check the result.') + `<div class="actions">${button('Check this Mac','tools',{},true)}${guideLink(page === 'tools' ? 'install-cli-tools.html' : 'optional-cli-tools.html')}</div>` + (page === 'optional' ? note('Go and Zig use the Apple Silicon versions pinned in your original guide. Review those versions for the project you’re building. Ghostty build instructions are in Reference guides.') : '') + installers(i => i.id !== 'install' && i.optional === (page === 'optional')) + (page === 'tools' ? finish('tools') : '');
    } else if (page === 'brew') {
      html = title('Step 3 · Package manager','Homebrew','Use the official installer, then add brew to your login shell PATH.') + note('Install Command Line Tools first. This installer uses Terminal for password prompts and detects the Apple Silicon or Intel install location.') + installers(i => i.id === 'install') + `<div class="actions">${button('Check this Mac','tools')}${guideLink('install-homebrew.html')}</div>` + finish('brew');
    } else if (page === 'defaults' || page === 'gestures') html = preferences();
    else if (page === 'shell') {
      html = title('Step 6 · Shell','Faster Zsh startup','Keep tool paths ready, then load nvm and completions on first use. Your existing configuration is backed up before a change.') + `<div class="card"><h3>Your shell configuration</h3><p><code>${escape(state.shellPath)}</code></p><div class="actions">${button('Check & preview','shellCheck',{},true)}${button('Set up Zsh','shellApply')}${button('Choose ZDOTDIR folder','shellFolder')}</div></div><div class="card"><h3>What this changes</h3><p>Updates one marked section, disables recognized eager loader lines, keeps unrelated configuration, and validates the result with <code>zsh -n</code>. Rerunning the same setup creates no extra backup.</p><p>Backups live in the <code>backups</code> folder beside your .zshrc. The run log prints the exact path. Restore that file if needed, then open a new Terminal.</p><p>Custom frameworks, multiline loaders and plugins stay in place. First Tab and first Node command pay the deferred initialization cost.</p></div><div class="actions">${guideLink('setup-zsh.html')}${button('Check this Mac','tools')}</div>` + finish('shell');
    } else if (page === 'disk') html = diskPage();
    else if (page === 'guides') {
      html = title('Offline · Original reference','Reference guides','All ten pages from your macOS reset1 guide, with their scripts embedded. Links and installers still need internet access.') + state.guides.map(g => `<div class="card row"><div class="grow"><strong>${escape(g.title)}</strong></div><button data-guide="${g.file}">${icon('i-book')}Read guide</button></div>`).join('') + '<p class="subtle">Bundled snapshot: October 2, 2026. These guides preserve the source instructions and pinned versions. Native actions use the simpler workflows on the setup pages.</p>';
    }
    $('main').innerHTML = html;
    // Bar widths are set through the style object: the page's CSP forbids inline style attributes.
    document.querySelectorAll('[data-w]').forEach(bar => { bar.style.width = bar.dataset.w + '%'; });
  }
  function showPage(id) {
    if (!pages.some(p => p[0] === id)) return;
    page = id; search = ''; renderNav(); renderMain(); $('main').scrollTop = 0; $('main').focus({preventScroll:true});
  }
  window.receive = payload => {
    if (payload.type === 'notice') { notice(payload.text); return; }
    if (payload.type !== 'state') return;
    const focused = document.activeElement;
    const setting = focused?.dataset?.setting;
    const cursor = focused?.id === 'search' ? focused.selectionStart : null;
    const before = state?.disk?.path;
    const scroll = page === 'disk' && payload.disk && payload.disk.path !== before ? 0 : $('main').scrollTop;
    state = payload; renderNav(); renderMain(); $('main').scrollTop = scroll;
    if (cursor !== null && $('search')) { $('search').focus(); $('search').setSelectionRange(cursor,cursor); }
    if (setting) document.querySelector(`[data-setting="${setting}"]`)?.focus({preventScroll:true});
  };
  document.addEventListener('click', event => {
    const node = event.target.closest('button'); if (!node || node.disabled) return;
    if (node.dataset.page) showPage(node.dataset.page);
    if (node.dataset.action) post(node.dataset.action,JSON.parse(node.dataset.extra || '{}'));
    if (node.dataset.guide) {
      $('guide-title').textContent = state.guides.find(g => g.file === node.dataset.guide)?.title || 'Reference guide';
      $('guide-frame').src = 'guides/' + node.dataset.guide; $('guide').showModal();
    }
    if (node.dataset.selection) {
      const ids = new Set(state.selected);
      document.querySelectorAll('[data-setting]').forEach(input => node.dataset.selection === 'all' ? ids.add(input.dataset.setting) : ids.delete(input.dataset.setting));
      post('select',{ids:[...ids]});
    }
  });
  document.addEventListener('change', event => {
    const target = event.target;
    if (target.dataset.setting) {
      const ids = new Set(state.selected); target.checked ? ids.add(target.dataset.setting) : ids.delete(target.dataset.setting); post('select',{ids:[...ids]});
    }
    if (target.dataset.complete) post('complete',{id:target.dataset.complete,value:target.checked});
  });
  document.addEventListener('input', event => {
    if (event.target.id !== 'search') return;
    const cursor = event.target.selectionStart; search = event.target.value; renderMain(); $('search').focus(); $('search').setSelectionRange(cursor,cursor);
  });
  // Run log height: drag the top edge, or focus it and use the arrow keys. Remembered between launches.
  const LOG_DEFAULT = 150, LOG_MIN = 56;
  const logMax = () => Math.max(LOG_MIN, window.innerHeight - 52 - 220);
  let logHeight = LOG_DEFAULT;
  function setLogHeight(value, save = false) {
    logHeight = Math.round(Math.min(logMax(), Math.max(LOG_MIN, value)));
    document.documentElement.style.setProperty('--log-h', logHeight + 'px');
    const bar = $('log-splitter');
    bar.setAttribute('aria-valuemin', LOG_MIN); bar.setAttribute('aria-valuemax', logMax()); bar.setAttribute('aria-valuenow', logHeight);
    if (save) { try { localStorage.setItem('logHeight', String(logHeight)); } catch (error) { /* storage can be unavailable */ } }
  }
  try { const saved = Number(localStorage.getItem('logHeight')); setLogHeight(saved > 0 ? saved : LOG_DEFAULT); } catch (error) { setLogHeight(LOG_DEFAULT); }
  window.addEventListener('resize', () => setLogHeight(logHeight));
  $('log-splitter').addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    const bar = event.currentTarget, startY = event.clientY, startHeight = logHeight;
    bar.setPointerCapture(event.pointerId); document.body.classList.add('resizing');
    const move = e => setLogHeight(startHeight + startY - e.clientY);
    const stop = () => { bar.removeEventListener('pointermove', move); bar.removeEventListener('pointerup', stop); bar.removeEventListener('pointercancel', stop); document.body.classList.remove('resizing'); setLogHeight(logHeight, true); };
    bar.addEventListener('pointermove', move); bar.addEventListener('pointerup', stop); bar.addEventListener('pointercancel', stop);
    event.preventDefault();
  });
  $('log-splitter').addEventListener('keydown', event => {
    const step = event.shiftKey ? 96 : 24;
    const next = { ArrowUp: logHeight + step, ArrowDown: logHeight - step, Home: logMax(), End: LOG_MIN }[event.key];
    if (next === undefined) return;
    event.preventDefault(); setLogHeight(next, true);
  });
  $('log-splitter').addEventListener('dblclick', () => setLogHeight(LOG_DEFAULT, true));
  $('close-guide').addEventListener('click', () => $('guide').close());
  $('cancel').addEventListener('click', () => post('cancel'));
  $('copy-log').addEventListener('click', () => post('copyLog'));
  $('toggle-log').addEventListener('click', () => {
    $('log').hidden = !$('log').hidden; $('log-splitter').hidden = $('log').hidden; $('toggle-log').textContent = $('log').hidden ? 'Show' : 'Hide'; $('toggle-log').setAttribute('aria-expanded',String(!$('log').hidden));
  });
  post('ready');
})();
