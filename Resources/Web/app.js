(() => {
  'use strict';
  // [id, label, mark (step number or icon), group heading shown above it, breadcrumb group]
  const pages = [
    ['overview','Overview','i-layers','','Start'],
    ['permissions','Permissions','i-shield','','Start'],
    ['clt','Command Line Tools','1','Setup, in order','Setup'],
    ['tools','CLI tools','2','','Setup'],
    ['brew','Homebrew','3','','Setup'],
    ['shell','faster zsh startup','4','','Setup'],
    ['defaults','macOS defaults','5','','Setup'],
    ['gestures','Accessibility & gestures','6','','Setup'],
    ['chrome','Google Chrome','i-globe','Apps','Apps'],
    ['accessibility','Reading & typing','i-access','Accessibility','Accessibility'],
    ['functions','Shell functions','i-terminal','Extras','Extras'],
    ['optional','Optional CLI tools','i-plus','','Extras'],
    ['disk','Disk usage','i-disk','','Extras'],
    ['guides','Reference guides','i-book','','Extras'],
  ];
  const steps = ['clt','tools','brew','shell','defaults','gestures'];
  const $ = id => document.getElementById(id);
  const escape = text => String(text).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const label = id => pages.find(p => p[0] === id)[1];
  let state = null, page = 'overview', search = '', preferenceFilter = 'all';
  // Interface sounds after Drafting Paper: synthesized with Web Audio, so there are no audio files. They only answer
  // something you did (a click, or a job you started finishing), stay quiet, and always pair with a visible change.
  const sound = (() => {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    let ctx = null, enabled = true;
    try { enabled = localStorage.getItem('sound') !== 'off'; } catch (error) { /* storage can be unavailable */ }
    const SCALE = [523.25, 587.33, 659.25, 783.99, 880, 987.77];     // C5 D5 E5 G5 A5 B5, one pentatonic family
    function tone(freq, dur, { type = 'sine', gain = .05, delay = 0, to = 0 } = {}) {
      try { ctx ??= new AudioCtx(); } catch (error) { return; }
      if (ctx.state === 'suspended') ctx.resume();
      const t = ctx.currentTime + delay, osc = ctx.createOscillator(), amp = ctx.createGain();
      osc.type = type; osc.frequency.setValueAtTime(freq, t);
      if (to) osc.frequency.exponentialRampToValueAtTime(to, t + dur);
      amp.gain.setValueAtTime(.0001, t);
      amp.gain.exponentialRampToValueAtTime(gain, t + .01);
      amp.gain.exponentialRampToValueAtTime(.0001, t + dur);
      osc.connect(amp).connect(ctx.destination); osc.start(t); osc.stop(t + dur + .03);
    }
    // Every preset takes (position, delay). Position pitches list-like sounds; the rest ignore it.
    const presets = {
      tap: (_, d) => { tone(560, .05, { type: 'triangle', gain: .05, delay: d, to: 420 }); tone(220, .07, { gain: .03, delay: d }); },
      select: (i, d) => tone(SCALE[Math.max(0, i) % SCALE.length], .08, { gain: .04, delay: d }),
      destructive: (_, d) => { tone(140, .16, { type: 'triangle', gain: .07, delay: d, to: 90 }); tone(70, .2, { gain: .06, delay: d }); },
      on: (_, d) => { tone(392, .07, { gain: .045, delay: d }); tone(523.25, .12, { gain: .045, delay: d + .07 }); },
      off: (_, d) => { tone(523.25, .07, { gain: .04, delay: d }); tone(392, .12, { gain: .04, delay: d + .07 }); },
      success: (_, d) => [523.25, 659.25, 783.99, 1046.5].forEach((f, k) => tone(f, .26, { gain: .05, delay: d + k * .08 })),
      error: (_, d) => [0, .14].forEach(x => tone(170, .12, { type: 'square', gain: .03, delay: d + x, to: 120 })),
      notice: (_, d) => { tone(880, .28, { gain: .04, delay: d }); tone(1760, .2, { gain: .012, delay: d }); },
    };
    return {
      get enabled() { return enabled; },
      set enabled(value) { enabled = !!value; try { localStorage.setItem('sound', enabled ? 'on' : 'off'); } catch (error) { /* storage can be unavailable */ } },
      // force: the Sounds switch itself always answers, so turning sound off is still heard once.
      play(name, position = 0, { delay = 0, force = false } = {}) {
        if (presets[name] && AudioCtx && (force || enabled)) presets[name](position, delay);
      },
    };
  })();
  const post = (action, extra = {}) => {
    if (window.webkit?.messageHandlers?.reset1) window.webkit.messageHandlers.reset1.postMessage({action,...extra});
    else notice('This action is available in the native Mac app.');
  };
  const icon = (name, extra = '') => `<svg class="icon ${extra}" aria-hidden="true"><use href="#${name}"/></svg>`;
  function notice(text) { $('toast-text').textContent = text; $('toast').hidden = false; sound.play('notice', 0, { delay: .06 }); clearTimeout(notice.timer); notice.timer = setTimeout(() => $('toast').hidden = true, 2600); }
  // kind: true for the one primary action in view, or a class list such as 'ghost sm'.
  function button(text, action, extra = {}, kind = '', glyph = '') {
    const cls = kind === true ? 'primary' : kind || '';
    return `<button ${cls ? `class="${cls}"` : ''} data-action="${action}" data-extra="${escape(JSON.stringify(extra))}" ${state.busy ? 'disabled' : ''}>${glyph ? icon(glyph) : ''}${escape(text)}</button>`;
  }
  // go: a button that opens another page of the app. link: a link that leaves the app for the browser.
  const go = (id, html, kind = '') => `<button ${kind ? `class="${kind}"` : ''} data-page="${id}">${html}</button>`;
  const link = (href, text, kind = '') => `<a class="btn ${kind}" href="${escape(href)}">${escape(text)}${icon('i-external')}</a>`;
  function guideLink(file) { return `<button data-guide="${file}">${icon('i-book')}Read reference guide</button>`; }
  function note(html, glyph = 'i-info', kind = '', action = '') { return `<div class="alert ${kind} ${action ? 'has-action' : ''}">${icon(glyph)}<p>${html}</p>${action}</div>`; }
  const blockedPermissions = () => (state.permissions || []).filter(p => p.status === 'missing');
  function title(kicker, heading, description) { return `<p class="eyebrow">${kicker}</p><h1>${heading}</h1><p class="lede">${description}</p>`; }
  // The end of a setup step: tick it off, then go on. The button leads once the step is ticked.
  function finish(id) {
    const done = state.completed.includes(id), next = steps[steps.indexOf(id) + 1];
    return `<div class="finish"><label><input type="checkbox" data-complete="${id}" ${done ? 'checked' : ''} ${state.busy ? 'disabled' : ''}><span>I’ve finished this step on this Mac</span></label>` +
      go(next || 'overview', `${next ? `Next: ${label(next)}` : 'Back to Overview'}${icon('i-arrow')}`, done ? 'primary' : '') + '</div>';
  }
  // A unified diff with each line as its own block, so added and removed lines can be tinted.
  function diff(text) {
    return `<pre class="command diff">${text.split('\n').map(line => `<span class="${/^(\+\+\+|---|@@)/.test(line) ? 'meta' : line[0] === '+' ? 'add' : line[0] === '-' ? 'del' : ''}">${escape(line)}</span>`).join('')}</pre>`;
  }
  // The .zshrc that Zsh setup and Shell functions write to.
  function target(extra = '') {
    return `<div class="card target"><div class="row"><span class="dicon">${icon('i-file')}</span><div class="grow"><strong>Your .zshrc</strong><code class="spath">${escape(state.shellPath)}</code></div><div class="actions">${extra}${button('Choose shell folder','shellFolder',{},'ghost sm','i-folder')}</div></div></div>`;
  }
  function renderNav() {
    const mark = (id, n) => state.completed.includes(id) ? icon('i-check') : n.startsWith('i-') ? icon(n) : n;
    const blocked = blockedPermissions().length;
    const flag = id => id === 'permissions' && blocked ? `<span class="badge badge-warning nav-flag" title="${blocked} not allowed">${blocked}</span>` : '';
    $('nav').innerHTML = pages.map(([id,label,n,group]) => `${group ? `<div class="group">${group}</div>` : ''}<button data-page="${id}" ${page === id ? 'aria-current="page"' : ''}><span class="number ${state.completed.includes(id) ? 'done' : ''}">${mark(id, n)}</span>${label}${flag(id)}</button>`).join('');
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
    $('log-peek').textContent = state.log.split('\n')[0];
  }
  // What the last check found for one tool: a badge beside its name, then the version and path underneath.
  const TOOL = { installed: ['Detected','badge-success'], missing: ['Not found','badge-warning'], failed: ['Check failed','badge-danger'] };
  function toolBadge(id) {
    const result = state.toolResults?.[id];
    if (!result) return '<span class="badge badge-plain">Not checked</span>';
    const [text, cls] = TOOL[result.status] || ['Unknown','badge-plain'];
    return `<span class="badge ${cls}">${text}</span><span class="checked">Checked ${ago(result.checkedAt)}</span>`;
  }
  function toolDetail(id) {
    const result = state.toolResults?.[id];
    if (!result || !(result.version || result.path || result.detail)) return '';
    return `<div class="found">${result.version ? `<span>${escape(result.version)}</span>` : ''}${result.path ? `<code>${escape(result.path)}</code>` : ''}${result.detail ? `<p>${escape(result.detail)}</p>` : ''}</div>`;
  }
  // On a page about one tool, one button leads: check first, install only once a check has found nothing.
  function toolLead(id) {
    const status = state.toolResults?.[id]?.status;
    return !status || status === 'failed' ? 'check' : status === 'missing' ? 'install' : '';
  }
  function toolLinks(item) {
    return [['website', 'Website'], ['docs', 'Docs']].filter(([key]) => item[key]?.startsWith('https://')).map(([key,text]) => `<a class="btn ghost sm" href="${escape(item[key])}" aria-label="${escape(item.name + ' ' + text)}">${text}${icon('i-external')}</a>`).join('');
  }
  function toolCard(item, { lead = '', heading = item.name, about = '' } = {}) {
    return `<article class="card tool"><div class="row"><h3 class="grow">${escape(heading)}${toolBadge(item.id)}</h3>` +
      `<div class="actions">${toolLinks(item)}${button('Check installation','toolCheck',{id:item.id},lead === 'check','i-refresh')}${button('Install in Terminal','installer',{id:item.id},lead === 'install','i-terminal')}</div></div>` +
      `${toolDetail(item.id)}${about || (item.note ? `<p>${escape(item.note)}</p>` : '')}<details><summary>Review installer command</summary><pre class="command">${escape(item.command)}</pre></details></article>`;
  }
  // One preference row. Its value shows as a transition only when a check found it would change or could not be read.
  // A choice row (Appearance, Icon & widget style) offers its options in a select instead of one fixed value.
  const RESULT = { set: ['Already set','badge-success'], change: ['Would change','badge-accent'], failed: ['Failed','badge-danger'] };
  function preferenceRow(s) {
    const result = state.preferenceResults?.[s.id];
    const [text, cls] = result ? RESULT[result.status] || ['Unknown','badge-plain'] : ['Not checked','badge-plain'];
    const before = result && result.status !== 'set' ? result.current ?? (result.status === 'failed' ? 'Unreadable' : 'Not set') : null;
    const proposed = s.options
      ? `<span class="select"><select data-choice="${s.id}" aria-label="${escape(s.description)}" ${state.busy ? 'disabled' : ''}>${s.options.map(o => `<option value="${escape(o.id)}" ${state.choices?.[s.id] === o.id ? 'selected' : ''}>${escape(o.label)}</option>`).join('')}</select></span>`
      : `<span class="sr">Proposed: </span><code class="value" title="${escape(s.value)}">${escape(s.value)}</code>`;
    const change = `<span class="change">${before === null ? '' : `<span class="sr">Current: </span><code class="value was" title="${escape(before)}">${escape(before)}</code><span aria-hidden="true">→</span>`}${proposed}</span>`;
    const keys = s.options ? [...new Set(s.options.flatMap(o => o.writes.map(w => w.key)))].join(', ') : s.key;
    return `<label class="setting"><input type="checkbox" data-setting="${s.id}" ${state.selected.includes(s.id) ? 'checked' : ''} ${state.busy ? 'disabled' : ''}><span class="text"><strong>${escape(s.description)}${s.domain === 'com.apple.universalaccess' ? '<span class="badge badge-warning">Protected</span>' : ''}</strong><small>${escape(s.domain)} · ${escape(keys)}${s.currentHost ? ' · this Mac' : ''}</small>${s.note ? `<span class="detail">${escape(s.note)}</span>` : ''}${result?.detail ? `<span class="detail ${result.status === 'failed' ? 'problem' : ''}">${escape(result.detail)}</span>` : ''}</span><span class="result">${change}<span class="state"><span class="badge ${cls}" ${result ? `title="Checked ${ago(result.checkedAt)}"` : ''}>${text}</span></span></span></label>`;
  }
  function chromePage() {
    const lead = toolLead('chrome'), chrome = state.installers.find(i => i.id === 'chrome');
    return title('Apps · Web browser', 'Google Chrome', 'Check whether Chrome is already on this Mac. If it is not, install it one of two ways.') +
      `<article class="card tool"><div class="row"><h3 class="grow">Google Chrome${toolBadge('chrome')}</h3><div class="actions">${chrome ? toolLinks(chrome) : ''}${button('Check installation','toolCheck',{id:'chrome'},lead === 'check','i-refresh')}</div></div>${toolDetail('chrome')}<p>The check looks in Applications and in your personal Applications folder. It does not open Chrome.</p></article>` +
      `<h2>Install it one of two ways</h2><div class="choices">` +
      `<article class="card"><h3>Download from Google</h3><p>Open the downloaded file, then drag Google Chrome into Applications.</p><div class="actions">${link('https://www.google.com/chrome/','Download Chrome from Google',lead === 'install' ? 'primary' : '')}</div></article>` +
      `<article class="card"><h3>Install with Homebrew</h3><p>Runs this command in Terminal. Homebrew has to be installed first.</p><pre class="command">brew install --cask google-chrome</pre><div class="actions">${button('Install with Homebrew','installer',{id:'chrome'},'','i-terminal')}${go('brew','Set up Homebrew')}</div></article></div>` +
      `<p class="subtle">Both ways need internet. When the install finishes, come back and choose Check installation.</p>`;
  }
  function accessibilityPage() {
    const method = (name, about, actions, fold = '') => `<li class="method"><div class="grow"><strong>${name}</strong><p>${about}</p></div><div class="actions">${actions}</div>${fold}</li>`;
    const fold = (summary, about, code) => `<details><summary>${summary}</summary><p class="subtle">${about}</p><pre class="command">${escape(code)}</pre></details>`;
    return title('Accessibility · Reading & typing', 'Reading & typing', 'Each setting has four ways to turn it on. Pick one. If the setting is already on, leave it.') +
      note('<strong>The app cannot see the switch.</strong> Opening a pane or starting a script does not prove the setting is on. Look at the switch in System Settings, or read the last line the script or Codex prints.') +
      (state.accessibilityActions || []).map(item => `<article class="card"><h3>${escape(item.name)}</h3><p>${escape(item.description)}</p><ul class="methods">` +
        method('In System Settings', `Open the pane and switch on <b>${escape(item.name)}</b> yourself. Path: ${escape(item.path)}.${item.path.includes('Read & Speak') ? ' Older macOS calls Read &amp; Speak “Spoken Content”.' : ''}`,
          button('Open settings','settings',{id:item.settingsID},true,'i-external') + link(item.help,'Apple instructions','ghost')) +
        method('AppleScript in Terminal', 'Reads the switch, clicks it once only if it is off, then confirms it is on.',
          button('Enable with AppleScript','accessibilityRunScript',{id:item.id},'','i-terminal') + button('Copy script','accessibilityCopyScript',{id:item.id},'ghost','i-copy'),
          fold('Permissions and script', 'macOS may ask you to allow Terminal under Privacy &amp; Security → Accessibility, and to let it control System Events and System Settings. If the script cannot find the exact switch, it stops without clicking. It does not need Full Disk Access.', item.script)) +
        method('Codex app with GPT-6 Luna', 'Opens a prepared chat. Choose <b>GPT-6 Luna</b> in the model picker, then send it. Codex uses computer use to turn the setting on and verify it.',
          button('Open Codex prompt','accessibilityCodex',{id:item.id},'','i-external') + button('Copy prompt','accessibilityCopyPrompt',{id:item.id},'ghost','i-copy'),
          fold('Requirements and prompt', 'Needs the Codex app with computer use turned on and GPT-6 Luna available. The button only fills in the prompt. You choose the model and send it. Follow any permission prompts Codex shows.', item.prompt)) +
        method('Codex CLI with GPT-6 Luna', 'Starts a Terminal session with GPT-6 Luna. Codex runs the AppleScript above and reports its result.',
          button('Run Codex CLI','accessibilityRunCLI',{id:item.id},'','i-terminal') + button('Copy CLI command','accessibilityCopyCLI',{id:item.id},'ghost','i-copy'),
          fold('Requirements and command', 'Needs the Codex CLI, a signed-in account and access to GPT-6 Luna. Approve the UI automation command when Codex asks. Terminal needs the same macOS permissions as the AppleScript method. This uses your Codex account and may count against your usage.', item.cliCommand || '')) +
        '</ul></article>').join('');
  }
  // The System Settings pane behind each group on the Accessibility & gestures page.
  const PANES = { 'Mission Control': ['trackpad','Trackpad settings'], 'Zoom': ['zoom','Zoom settings'], 'Accessibility Keyboard': ['keyboard','Keyboard settings'] };
  function preferences() {
    const all = state.settings.filter(s => s.section === page);
    const status = s => state.preferenceResults?.[s.id]?.status || 'unchecked';
    const shown = all.filter(s => `${s.group} ${s.description} ${s.key} ${(s.options || []).map(o => o.label).join(' ')}`.toLowerCase().includes(search.toLowerCase()) && (preferenceFilter === 'all' || status(s) === preferenceFilter));
    const groups = [...new Set(shown.map(s => s.group))];
    const count = all.filter(s => state.selected.includes(s.id)).length;
    const tally = name => all.filter(s => status(s) === name).length;
    const checked = all.length - tally('unchecked');
    const protectedPage = page === 'gestures';
    const fullDisk = (state.permissions || []).find(p => p.id === 'fda')?.status;
    const found = checked
      ? `<p><b>${tally('change')}</b> would change · <b>${tally('set')}</b> already set${tally('failed') ? ` · <b>${tally('failed')}</b> failed` : ''}${tally('unchecked') ? ` · <b>${tally('unchecked')}</b> not checked` : ''}</p><p class="checked">Checked ${ago(Math.max(...all.map(s => state.preferenceResults?.[s.id]?.checkedAt || 0)))}</p>`
      : '<p>Reads every preference on this page. Nothing is written.</p>';
    const options = [['all','All'],['change','Would change'],['failed','Failed'],['set','Already set'],['unchecked','Not checked']].map(([value,text]) => `<option value="${value}" ${preferenceFilter === value ? 'selected' : ''}>${text} (${value === 'all' ? all.length : tally(value)})</option>`).join('');
    const heading = group => protectedPage && PANES[group] ? `<div class="section-head"><h2>${escape(group)}</h2>${button(PANES[group][1],'settings',{id:PANES[group][0]},'ghost sm','i-external')}</div>` : `<h2>${escape(group)}</h2>`;
    return title(protectedPage ? 'Step 6 · Accessibility' : 'Step 5 · Preferences', label(page), protectedPage ? 'Mission Control swipe, Zoom and the Accessibility Keyboard. Work through the three steps below.' : 'Finder, Dock, keyboard, screenshot and other everyday preferences. Work through the three steps below.') +
      (protectedPage && fullDisk !== 'granted' ? note('<strong>Zoom and Accessibility Keyboard rows need Full Disk Access.</strong> Turn it on for ArfanReset1, then quit and reopen the app. Those rows start unselected.', 'i-shield', fullDisk === 'missing' ? 'alert-warning' : '', button('Full Disk Access','settings',{id:'privacy'},'sm','i-external')) : '') +
      `<ol class="flow"><li><h3>Check</h3>${found}<div class="actions">${button('Check current values','check',{section:page},!checked,'i-refresh')}</div></li>` +
      `<li><h3>Choose</h3><p>Select the rows you want written. The rest stay as they are.</p><p><b>${count}</b> of ${all.length} selected</p></li>` +
      `<li><h3>Apply</h3><p>Saves a backup, writes each selected row, then reads it back. Some changes need a logout.</p><div class="actions">${count ? button(`Apply ${count} selected`,'apply',{section:page},!!checked) : '<button disabled>Apply 0 selected</button>'}${button('Restart Finder & Dock','restart')}</div></li></ol>` +
      `<div class="toolbar"><div class="input-icon">${icon('i-search')}<input type="search" id="search" aria-label="Find a preference" placeholder="Find a preference…" value="${escape(search)}"></div><label class="select">Show<select id="preference-filter">${options}</select></label><button data-selection="all" ${state.busy ? 'disabled' : ''}>Select shown</button><button data-selection="none" ${state.busy ? 'disabled' : ''}>Deselect shown</button><small>${shown.length} shown · ${count} selected on this page</small></div>` +
      (groups.length ? groups.map(group => `${heading(group)}<div class="settings-group">${shown.filter(s => s.group === group).map(preferenceRow).join('')}</div>`).join('') : `<div class="empty">${icon('i-inbox')}<h4>No preferences match</h4><p>Clear the search, or set Show to All.${preferenceFilter !== 'all' && !checked ? ' The result filters stay empty until you check current values.' : ''}</p></div>`) +
      `<h2>Undo and details</h2><p class="subtle">Restore puts back the values from before your last Apply, on whichever page you ran it. Apply confirms that each value was saved, but macOS can ignore a key it no longer supports.</p><div class="actions">${state.hasBackup ? button('Restore last preference backup','restore',{},'','i-undo') : ''}${button('Show backups & logs','reveal',{},'','i-folder')}${guideLink(protectedPage ? 'setup-defaults2.html' : 'setup-defaults.html')}</div>` + finish(page);
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
      `<ul class="legend">${[['here', name, here], ['other', 'Everything else', used - here], ['free', 'Available', d.volumeAvailable]].map(([sw, label, bytes]) => `<li><i class="sw ${sw}"></i>${label} <b>${size(bytes)}</b><span class="pct">${share(percent(bytes, d.volumeTotal))}</span></li>`).join('')}</ul></div>`;
  }
  // Folders and files in two lists (the default), or one list by size. Remembered in this browser.
  const DISK_LIMIT = 60;   // DiskUsage.limit: the combined list shows the largest 60; the rest share one row
  let diskSplit = true;
  try { diskSplit = localStorage.getItem('diskSplit') !== '0'; } catch (error) { /* storage can be unavailable */ }
  const total = list => list.reduce((sum, e) => sum + e.bytes, 0);
  function diskRow(d, e, largest) {
    const label = e.isDirectory
      ? `<button class="link" data-action="disk" data-extra="${escape(JSON.stringify({path:e.path}))}" ${state.busy ? 'disabled' : ''} title="${(state.diskSaved || []).includes(e.path) ? 'Open the saved scan of' : 'Scan inside'} ${escape(e.name)}">${escape(e.name)}</button>`
      : `<span class="fname">${escape(e.name)}</span>`;
    return `<li class="drow"><span class="dicon">${icon(e.isDirectory ? 'i-folder' : 'i-file')}</span><span class="dname">${label}</span><span class="dbar" aria-hidden="true"><i data-w="${percent(e.bytes, largest)}"></i></span><span class="dsize">${size(e.bytes)}</span><span class="dshare" title="Share of this folder">${share(percent(e.bytes, d.bytes))}</span><button class="sm ghost icon-only" data-action="diskReveal" data-extra="${escape(JSON.stringify({path:e.path}))}" aria-label="Show ${escape(e.name)} in Finder" title="Show in Finder">${icon('i-reveal')}</button></li>`;
  }
  function diskList(d, entries, moreCount, moreBytes, noun) {
    const largest = entries.length ? entries[0].bytes : 0;
    const more = moreCount > 0 ? `<li class="drow more"><span class="dicon"></span><span class="dname">${moreCount} smaller ${moreCount === 1 ? noun[0] : noun[1]}</span><span class="dbar"></span><span class="dsize">${size(moreBytes)}</span><span class="dshare">${share(percent(moreBytes, d.bytes))}</span><span></span></li>` : '';
    return `<ul class="dlist">${entries.map(e => diskRow(d, e, largest)).join('')}${more}</ul>`;
  }
  function diskRows(d) {
    if (!d.entries.length) return `<div class="empty">${icon('i-inbox')}<h4>This folder is empty</h4><p>Nothing to measure here. Pick another folder from the path above.</p></div>`;
    if (!diskSplit) return diskList(d, d.entries.slice(0, DISK_LIMIT), d.moreCount, d.moreBytes, ['item', 'items']);
    // Scans saved before the split view only know the largest items overall, so their kinds have no "smaller" row.
    return [['Folders', true, d.folders, ['folder', 'folders']], ['Files', false, d.files, ['file', 'files']]].map(([heading, isDirectory, kind, noun]) => {
      const entries = d.entries.filter(e => e.isDirectory === isDirectory);
      const count = kind?.count ?? entries.length, bytes = kind?.bytes ?? total(entries);
      const body = count
        ? diskList(d, entries, count - entries.length, bytes - total(entries), noun)
        : `<p class="dnone">No ${noun[1]} directly in this folder.</p>`;
      return `<section class="dsection" aria-label="${heading}"><div class="dsub"><h4>${icon(isDirectory ? 'i-folder' : 'i-file')}${heading}</h4><span><b>${size(bytes)}</b> · ${share(percent(bytes, d.bytes))} · ${count} ${count === 1 ? noun[0] : noun[1]}</span></div>${body}</section>`;
    }).join('') + (!d.folders && d.moreCount ? `<p class="dnone">Refresh to sort the ${d.moreCount} smaller items into folders and files.</p>` : '');
  }
  const itemCount = d => d.folders ? d.folders.count + d.files.count : d.entries.length + d.moreCount;
  function diskPage() {
    const d = state.disk;
    const head = title('Tool · Read only', 'Disk usage', 'See what is taking space in your home folder, then open any folder to look inside. The scan only reads; nothing is deleted or moved.');
    const tools = `<div class="actions">${d ? button('Refresh', 'disk', {path:d.path, refresh:true}, true, 'i-refresh') : button('Scan home folder', 'disk', {}, true, 'i-disk')}${d && d.path !== d.home ? button('Back to home folder', 'disk') : ''}${button('Storage settings','settings',{id:'storage'})}${button('Full Disk Access','settings',{id:'privacy'})}${d ? `<label class="switch"><input type="checkbox" role="switch" id="disk-split" ${diskSplit ? 'checked' : ''}><span class="track" aria-hidden="true"></span><span>Folders and files apart</span></label>` : ''}${d ? `<span class="saved" title="${escape(new Date(d.scannedAt * 1000).toLocaleString())}">${icon('i-clock')}Scanned ${ago(d.scannedAt)}</span>` : ''}</div>`;
    if (!d) {
      return head + tools + (state.busy
        ? `<div class="empty"><div class="scanning" aria-hidden="true"><i></i></div><h4>Scanning your home folder…</h4><p>You can open another page while this runs. Results appear here when the scan finishes.</p></div>`
        : `<div class="empty">${icon('i-disk')}<h4>No scan yet</h4><p>Scan your home folder to see which folders take the most space. Protected folders may be skipped unless the app has Full Disk Access.</p></div>`);
    }
    const skipped = d.unreadable > 0 ? note(`${d.unreadable} ${d.unreadable === 1 ? 'item' : 'items'} could not be read, so these totals may be low. Full Disk Access lets the app see more.`, 'i-alert') : '';
    return head + tools + volumeCard(d) + skipped +
      `<div class="card dcard ${state.busy ? 'is-busy' : ''}" aria-busy="${state.busy}">${state.busy ? '<div class="scanning" aria-hidden="true"><i></i></div>' : ''}<div class="dhead">${diskCrumbs(d)}<span class="dtotal"><b>${size(d.bytes)}</b> in ${itemCount(d)} ${itemCount(d) === 1 ? 'item' : 'items'} · ${share(percent(d.bytes, d.volumeTotal))} of the disk</span></div>${diskRows(d)}</div>` +
      `<p class="subtle">Scans are saved on this Mac, so a folder you have already opened appears instantly. Use Refresh after you change files. Sizes are space used on disk, in decimal units like Finder, and symbolic links are listed but not followed.</p>`;
  }
  const STATUS = { granted: ['Allowed','badge-success','i-check-circle'], missing: ['Needs attention','badge-warning','i-alert'], unknown: ['Unknown','badge-plain','i-help'] };
  function permissionsPage() {
    const list = state.permissions;
    const head = title('Before you start · Read only', 'Permissions', 'Fix anything marked Needs attention before you open the steps that use it. Checking only reads. It changes nothing and shows no macOS prompt.');
    const tools = `<div class="actions">${button('Check again','permissions',{log:true},true,'i-refresh')}${button('Full Disk Access','settings',{id:'privacy'},'','i-external')}${list ? `<span class="saved" title="${escape(new Date(state.permissionsCheckedAt * 1000).toLocaleString())}">${icon('i-clock')}Checked ${ago(state.permissionsCheckedAt)}</span>` : ''}</div>`;
    if (!list) return head + tools + `<div class="empty"><div class="scanning" aria-hidden="true"><i></i></div><h4>Checking permissions…</h4><p>Reading what macOS allows this app. It takes a moment.</p></div>`;
    const missing = list.filter(p => p.status === 'missing').length;
    const unknown = list.filter(p => p.status !== 'missing' && p.status !== 'granted').length;
    const allowed = list.filter(p => p.status === 'granted').length;
    const summary = note(`<strong>${allowed} allowed · ${missing} ${missing === 1 ? 'needs' : 'need'} attention · ${unknown} unknown.</strong> ${missing ? 'Each one below names the steps that need it.' : unknown ? 'Unknown means the check could not confirm access. Read its details before you use that step.' : 'Nothing is blocking a setup step.'} After you change Full Disk Access, quit and reopen the app.`, missing || unknown ? 'i-alert' : 'i-check-circle', missing || unknown ? 'alert-warning' : 'alert-success');
    const rows = list.map(p => {
      const [text, badge, glyph] = STATUS[p.status] || STATUS.unknown;
      return `<div class="perm perm-${escape(p.status)}"><span class="perm-icon">${icon(glyph)}</span><div class="grow"><strong>${escape(p.name)}</strong><p>${escape(p.detail)}</p><small>Used by ${escape(p.usedBy)}</small></div><div class="perm-side"><span class="badge ${badge}">${text}</span>${p.settings && p.status !== 'granted' ? button('Open settings','settings',{id:p.settings},'','i-external') : ''}</div></div>`;
    }).join('');
    return head + tools + summary + `<div class="card perms">${rows}</div>` +
      `<h2>What the app never asks for</h2><p class="subtle">ArfanReset1 never asks for Accessibility control, Automation, Screen Recording, Camera, Microphone, Contacts, Photos or Location.</p>` +
      `<p class="subtle">The Reading &amp; typing scripts run in Terminal, so macOS asks Terminal for Accessibility and Automation access, not this app.</p>` +
      `<p class="subtle">During a Disk usage scan, macOS may ask about Desktop, Documents or Downloads. Allow it, or turn on Full Disk Access, to include those folders.</p>`;
  }
  // The files Zsh setup touches, live from disk. The app only shows or opens them by id; it never takes a path from here.
  function shellFiles() {
    const files = state.shellFiles || [];
    const status = f => !f.exists ? 'Not created yet' : f.isFolder ? `${f.items} ${f.items === 1 ? 'backup' : 'backups'}` : 'Exists';
    const control = (text, extra, glyph = '', cls = 'sm') => `<button class="${cls}" data-action="shellFiles" data-extra="${escape(JSON.stringify(extra))}" ${state.busy ? 'disabled' : ''}>${glyph ? icon(glyph) : ''}${text}</button>`;
    const rows = files.map(f => `<li class="sfile ${f.exists ? '' : 'missing'}"><span class="dicon">${icon(f.isFolder ? 'i-folder' : 'i-file')}</span><div class="grow"><strong>${escape(f.name)}</strong><code class="spath">${escape(f.path)}</code><p>${escape(f.change)}</p></div><span class="badge badge-plain">${status(f)}</span><span class="sfile-tools">${f.exists && !f.isFolder ? control('Open', {id: f.id, open: true}) : ''}${control(f.isFolder && f.exists ? 'Open folder' : 'Show in Finder', {id: f.id})}</span></li>`).join('');
    return `<div class="card sfiles"><div class="row"><div class="grow"><h3>Files this step changes</h3><small>In ${escape(state.shellPath.replace(/\/[^/]*$/, '') || '/')}. Open shows a file in TextEdit. Looking at a file never changes it.</small></div>${control('Show all in Finder', {}, 'i-reveal', '')}</div><ul>${rows}</ul><p class="subtle">.zshrc and the completion cache are hidden files. If Finder does not select them, press <kbd>⌘</kbd><kbd>⇧</kbd><kbd>.</kbd> in that window to show hidden files.</p></div>`;
  }
  function functionsPage() {
    const functions = state.functions || [];
    return title('Extras · Shell shortcuts', 'Shell functions', 'Add ready-made commands to your .zshrc. Preview each change before you add it.') +
      target(button('Refresh status','functionStatus',{},'ghost sm','i-refresh')) +
      note('<strong>These functions need uv and their Python scripts.</strong> Install uv from CLI tools, and keep each script at the path shown on its card. Adding a function never runs its script.', 'i-info', '', go('tools','Open CLI tools','sm')) +
      functions.map(f => {
        const status = state.functionStatuses?.find(s => s.id === f.id);
        const [text, cls] = { installed: ['In your .zshrc','badge-success'], conflict: ['Needs review','badge-warning'] }[status?.status] || ['Not added yet','badge-plain'];
        const preview = state.functionPreview?.id === f.id && state.functionPreview.preview.path === state.shellPath ? state.functionPreview.preview : null;
        // Preview leads until a preview with changes is on screen; then adding is the next action.
        const lead = !status || status.status !== 'available' ? '' : preview?.changed ? 'add' : 'preview';
        return `<article class="card"><h3>${escape(f.name)}<span class="badge ${cls}">${text}</span></h3><p>${escape(f.description)}</p><p>Use it in Terminal: <code>${escape(f.usage)}</code></p>` +
          (status && status.status !== 'available' ? `<p>${escape(status.detail)}</p>` : '') +
          f.requirements.map(path => { const missing = status?.missing.includes(path); return `<p class="req ${missing ? 'missing' : ''}">${icon(missing ? 'i-alert' : 'i-check-circle')}<span>${missing ? 'Missing script' : 'Script found'}: <code>${escape(path)}</code></span></p>`; }).join('') +
          `<pre class="command">${escape(f.code)}</pre>` +
          `<div class="actions">${button('Preview changes','functionPreview',{id:f.id},lead === 'preview')}${status?.status === 'conflict' ? '<button disabled>Add to .zshrc</button>' : button('Add to .zshrc','functionApply',{id:f.id},lead === 'add')}${button('Copy function','functionCopy',{id:f.id},'ghost','i-copy')}</div>` +
          (preview ? `<h4>${preview.changed ? 'Review before adding' : 'Already up to date'}</h4><p>${preview.changed ? 'Lines that start with + are added (green). Lines that start with − are removed (red). Nothing has changed yet.' : 'Your .zshrc already has this exact function.'}</p>${preview.changed ? diff(preview.diff) : ''}` : '') + '</article>';
      }).join('') +
      `<h2>Undo and details</h2><p class="subtle">Adding a function saves a backup of .zshrc and checks the new file’s syntax first. To undo, restore a backup. Restore replaces the whole .zshrc, not one function.</p><div class="actions">${button('Restore Zsh backup','shellRestore',{},'','i-undo')}</div>` +
      `<details><summary>Add another function to this page</summary><p>Put its .zsh file in Resources/Functions, add an entry to Resources/Config/functions.json, then rebuild the app. Each function gets its own card and its own marked block in .zshrc.</p></details>`;
  }
  function renderMain() {
    if (!state) return;
    let html = '';
    if (page === 'overview') {
      const next = steps.find(id => !state.completed.includes(id));
      const blocked = blockedPermissions();
      const blurb = {clt:'Apple’s developer tools: Git, clang and make.',tools:'Deno, uv, Atuin, AI tools, nvm, Node.js and Bun.',brew:'Homebrew and its shell PATH.',defaults:'Choose and apply your everyday Mac preferences.',gestures:'Mission Control swipe, Zoom and the Accessibility Keyboard.',shell:'Back up .zshrc and defer heavy startup work.'};
      html = title('New Mac · after a reset', 'Make this Mac yours.', 'Start with the next step below. Your checklist is saved, so you can stop and come back.') +
        (next ? `<div class="card next beam"><p class="eyebrow">Next up · step ${steps.indexOf(next) + 1} of ${steps.length}</p><div class="row"><div class="grow"><h3>${escape(label(next))}</h3><p>${blurb[next]}</p></div>${go(next, `Open step ${steps.indexOf(next) + 1}${icon('i-arrow')}`, 'primary')}</div></div>`
              : `<div class="card next"><p class="eyebrow">All done</p><h3>All six steps are done</h3><p>Open any step again, or check which tools are installed now.</p></div>`) +
        (blocked.length ? note(`<strong>${escape(blocked.map(p => p.name).join(', '))}</strong> ${blocked.length === 1 ? 'is' : 'are'} not allowed yet. Permissions lists the steps that need ${blocked.length === 1 ? 'it' : 'them'}.`, 'i-alert', 'alert-warning', go('permissions','Review permissions','sm')) : '') +
        `<h2>All six steps</h2><div class="card steps">` +
        steps.map((id, i) => { const done = state.completed.includes(id); return `<div class="step ${done ? 'done' : ''}"><span class="step-num">${done ? icon('i-check') : i + 1}</span><div class="grow"><strong>${label(id)}</strong><small>${blurb[id]}</small></div><span class="badge ${done ? 'badge-success' : 'badge-plain'}">${done ? 'Done' : 'To do'}</span>${go(id,'Open','sm')}</div>`; }).join('') + '</div>' +
        `<div class="actions">${button('Check all tools','tools',{},!next,'i-refresh')}${button('Show backups & logs','reveal',{},'','i-folder')}</div>` +
        `<p class="subtle">The app itself needs no uv, Deno, Homebrew, Python or Xcode. Installers download from the internet and may ask for your password in Terminal.</p><p class="subtle">This Mac: ${escape(state.system)}</p>`;
    } else if (page === 'clt') {
      const clt = state.installers.find(i => i.id === 'clt');
      html = title('Step 1 · Apple developer tools', 'Command Line Tools', 'Git, clang and make from Apple. Check first. If they are missing, install them in Terminal and type your administrator password when it asks.') +
        (clt ? toolCard(clt, { lead: toolLead('clt'), heading: 'Install with Software Update', about: '<p>The installer finds the newest Command Line Tools package and installs it with <code>sudo softwareupdate</code>. If the tools are already here, it only prints their path and versions.</p>' }) : '') +
        `<div class="card"><h3>Alternative: Apple’s installer dialog</h3><p>Use this if the installer above finds no package, or if you prefer Apple’s own dialog. Follow its prompts, then check installation again.</p><pre class="command">xcode-select --install</pre><div class="actions">${button('Open installer dialog','clt')}</div></div>` +
        `<div class="card"><h3>Need all of Xcode?</h3><p>Xcode includes these tools plus the simulators and Interface Builder. It is a large download, and the setup steps here do not need it. Apple’s download page asks you to sign in with an Apple Account.</p><div class="actions">${link('https://apps.apple.com/app/xcode/id497799835','Xcode on the App Store')}${link('https://developer.apple.com/download/all/?q=xcode','Download Xcode from Apple')}${link('https://developer.apple.com/download/all/?q=command%20line%20tools','Command Line Tools downloads')}</div></div>` +
        finish('clt');
    } else if (page === 'tools' || page === 'optional') {
      const optional = page === 'optional';
      html = title(optional ? 'Optional · Developer tools' : 'Step 2 · Install what you use', label(page), 'Check what is already installed. Install only the tools you use, finish each installer’s prompts in Terminal, then check again.') +
        `<div class="actions">${button('Check all tools','tools',{},true,'i-refresh')}</div>` +
        (optional ? note('Go and Zig install the pinned Apple silicon versions shown in their installer commands. Check that those versions suit the project you are building.', 'i-info', '', `<button class="sm" data-guide="optional-builds.html">${icon('i-book')}Ghostty build guide</button>`) : '') +
        state.installers.filter(i => !['install','clt','chrome'].includes(i.id) && i.optional === optional).map(i => toolCard(i)).join('') + (optional ? '' : finish('tools'));
    } else if (page === 'brew') {
      const brew = state.installers.find(i => i.id === 'install');
      const cltReady = state.completed.includes('clt') || state.toolResults?.clt?.status === 'installed';
      html = title('Step 3 · Package manager', 'Homebrew', 'Check first. If Homebrew is missing, install it in Terminal.') +
        (cltReady ? '' : note('<strong>Install Command Line Tools first.</strong> That is step 1.', 'i-info', '', go('clt','Open step 1','sm'))) +
        (brew ? toolCard(brew, { lead: toolLead('install'), about: '<p>The installer asks for your password in Terminal, then adds brew to your PATH in <code>~/.zprofile</code>. It works on Apple silicon and Intel Macs.</p>' }) : '') +
        `<div class="actions">${guideLink('install-homebrew.html')}</div>` + finish('brew');
    } else if (page === 'defaults' || page === 'gestures') html = preferences();
    else if (page === 'shell') {
      const preview = state.shellPreview && state.shellPreview.path === state.shellPath ? state.shellPreview : null;
      html = title('Step 4 · Shell', label('shell'), 'Load nvm and completions on first use instead of at every startup. Your .zshrc is backed up before anything changes.') +
        target() +
        `<ol class="flow"><li><h3>Preview</h3><p>See the exact lines that would change. Nothing is written.</p><div class="actions">${button('Preview changes','shellCheck',{},!preview)}</div></li>` +
        `<li><h3>Set up</h3><p>Backs up .zshrc, then rewrites one marked block in it.</p><div class="actions">${button('Set up Zsh','shellApply',{},!!preview?.changed)}</div></li>` +
        `<li><h3>Open a new Terminal</h3><p>The new setup loads there. The first Tab and the first Node command take a little longer, once, while the deferred parts load.</p></li></ol>` +
        (preview ? `<div class="card"><h3>${preview.changed ? 'Review before setup' : 'Already up to date'}</h3><p>${preview.changed ? 'Lines that start with + are added (green). Lines that start with − are removed (red). Nothing has changed yet.' : 'Your .zshrc already has this setup. There is nothing to change.'}</p>${preview.changed ? diff(preview.diff) : ''}</div>` : '') +
        shellFiles() +
        `<h2>Undo and details</h2><p class="subtle">To undo, restore a backup. The app saves your current .zshrc first and checks the backup’s syntax.</p><div class="actions">${button('Restore Zsh backup','shellRestore',{},'','i-undo')}</div>` +
        `<details><summary>What setup keeps</summary><p>Setup rewrites one marked block and comments out the eager loader lines it recognizes. Everything else stays, including symlinks, file permissions, frameworks, plugins and multi-line loaders. The new file must pass a zsh syntax check before it replaces the old one. Running setup again with nothing to change makes no extra backup.</p></details>` + finish('shell');
    } else if (page === 'permissions') html = permissionsPage();
    else if (page === 'chrome') html = chromePage();
    else if (page === 'accessibility') html = accessibilityPage();
    else if (page === 'functions') html = functionsPage();
    else if (page === 'disk') html = diskPage();
    else if (page === 'guides') {
      html = title('Offline · Original reference', 'Reference guides', 'Terminal instructions kept from the original guide. For Command Line Tools, Homebrew and preferences, the setup pages do the same job with checks and backups. Building Ghostty is only covered here.') +
        `<div class="card list">${state.guides.map(g => `<div class="item"><span class="dicon">${icon('i-book')}</span><div class="grow"><strong>${escape(g.title)}</strong>${g.about ? `<small>${escape(g.about)}</small>` : ''}</div><button data-guide="${g.file}">Read guide</button></div>`).join('')}</div>` +
        '<p class="subtle">Snapshot from October 2, 2026, with its pinned versions. The text works offline. Downloads and external links need internet.</p>';
    }
    $('main').innerHTML = html;
    // Bar widths are set through the style object: the page's CSP forbids inline style attributes.
    document.querySelectorAll('[data-w]').forEach(bar => { bar.style.width = bar.dataset.w + '%'; });
  }
  function showPage(id) {
    if (!pages.some(p => p[0] === id)) return;
    page = id; search = ''; preferenceFilter = 'all'; renderNav(); renderMain(); $('main').scrollTop = 0; $('main').focus({preventScroll:true});
    if (id === 'permissions') post('permissions');   // quiet refresh; leaves the run log alone
  }
  window.receive = payload => {
    if (payload.type === 'notice') { notice(payload.text); return; }
    if (payload.type === 'done') { sound.play(payload.ok ? 'success' : 'error'); if (!payload.ok) { setLogCollapsed(false); notice('That action stopped or failed. The run log shows what finished.'); } return; }
    if (payload.type !== 'state') return;
    const focused = document.activeElement;
    const setting = focused?.dataset?.setting, complete = focused?.dataset?.complete, choice = focused?.dataset?.choice;
    const filterFocused = focused?.id === 'preference-filter';
    const openDetails = [...$('main').querySelectorAll('details')].map(d => d.open);
    const cursor = focused?.id === 'search' ? focused.selectionStart : null;
    const before = state?.disk?.path;
    const scroll = page === 'disk' && payload.disk && payload.disk.path !== before ? 0 : $('main').scrollTop;
    state = payload; renderNav(); renderMain(); $('main').scrollTop = scroll;
    if (cursor !== null && $('search')) { $('search').focus(); $('search').setSelectionRange(cursor,cursor); }
    $('main').querySelectorAll('details').forEach((d, i) => d.open = !!openDetails[i]);
    if (filterFocused) $('preference-filter')?.focus({preventScroll:true});
    if (setting) document.querySelector(`[data-setting="${setting}"]`)?.focus({preventScroll:true});
    if (complete) document.querySelector(`[data-complete="${complete}"]`)?.focus({preventScroll:true});
    if (choice) document.querySelector(`[data-choice="${choice}"]`)?.focus({preventScroll:true});
  };
  // Rail pages select, pitched by their place in the list; Stop is destructive; everything else taps.
  // data-sound="none" marks a button whose result already makes its own sound (a toast, a switch).
  function clickSound(node) {
    const named = node.dataset.sound;
    if (named === 'none') return;
    if (named) sound.play(named);
    else if (node.closest('nav')) sound.play('select', pages.findIndex(p => p[0] === node.dataset.page));
    else sound.play('tap');
  }
  document.addEventListener('click', event => {
    // A row is one big label. Choosing in its select must not also tick the row.
    if (event.target.closest('[data-choice]')) { event.preventDefault(); return; }
    const link = event.target.closest('a[href]'); if (link) { sound.play('tap'); return; }
    const node = event.target.closest('button'); if (!node || node.disabled) return;
    clickSound(node);
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
    if (target.id === 'preference-filter') { preferenceFilter = target.value; renderMain(); $('preference-filter').focus(); return; }
    if (target.dataset.choice) { sound.play('tap'); post('choose',{id:target.dataset.choice,option:target.value}); return; }
    if (target.id === 'disk-split') {
      diskSplit = target.checked;
      try { localStorage.setItem('diskSplit', diskSplit ? '1' : '0'); } catch (error) { /* storage can be unavailable */ }
      sound.play(diskSplit ? 'on' : 'off'); renderMain(); $('disk-split')?.focus(); return;
    }
    if (target.id === 'sound-switch') { sound.enabled = target.checked; sound.play(target.checked ? 'on' : 'off', 0, { force: true }); return; }
    // Finishing a step earns the chime; every other checkbox clicks on and off.
    if (target.type === 'checkbox') sound.play(target.checked ? (target.dataset.complete ? 'success' : 'on') : 'off');
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
  // Collapsed, the log shrinks to its bar and shows its first line (action and time). Remembered between launches.
  function setLogCollapsed(collapsed, save = false) {
    const toggle = $('toggle-log');
    $('log').hidden = collapsed; $('log-splitter').hidden = collapsed;
    document.querySelector('.run-log').classList.toggle('collapsed', collapsed);
    toggle.setAttribute('aria-expanded', String(!collapsed));
    toggle.querySelector('span').textContent = collapsed ? 'Expand' : 'Collapse';
    toggle.title = collapsed ? 'Show the run log' : 'Hide the run log';
    if (save) { try { localStorage.setItem('logCollapsed', collapsed ? '1' : '0'); } catch (error) { /* storage can be unavailable */ } }
  }
  try { setLogCollapsed(localStorage.getItem('logCollapsed') === '1'); } catch (error) { setLogCollapsed(false); }
  $('toggle-log').addEventListener('click', () => {
    const collapsed = !$('log').hidden;
    setLogCollapsed(collapsed, true); sound.play(collapsed ? 'off' : 'on');
  });
  $('sound-switch').checked = sound.enabled;
  post('ready');
})();
