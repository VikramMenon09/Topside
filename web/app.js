/* Topside web demo.
   Behaviour mirrors the Swift app: NotchModel (open/close, tabs, pin), the nine tab views in
   TabsA.swift / TabsB.swift, TimerService, PrompterService and the toast in ActivityCenter.
   Everything runs in the page. Data is sample data unless it comes from you (files you drop,
   text you copy here, your camera after you click). */
'use strict';
(() => {

// ---------- helpers ----------

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const ic = (n, s = 13, cls = '') => `<svg class="ic ${cls}" width="${s}" height="${s}" aria-hidden="true"><use href="#i-${n}"/></svg>`;
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const pad = n => String(n).padStart(2, '0');
const clock = sec => {
  const s = Math.max(0, Math.round(sec));
  return s >= 3600 ? `${Math.floor(s / 3600)}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}` : `${Math.floor(s / 60)}:${pad(s % 60)}`;
};
const ago = t => {
  const s = Math.floor((Date.now() - t) / 1000);
  if (s < 60) return 'now';
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
};
// IconButton: the frame is the symbol size + 12, with a circular 14% hover.
const ib = (icon, size, cls, label, attrs = '') =>
  `<button class="ib ${cls}" style="width:${size + 12}px;height:${size + 12}px" aria-label="${label}" title="${label}" ${attrs}>${ic(icon, size + 2)}</button>`;
const pill = (text, attrs = '', active = false) => `<button class="pill${active ? ' active' : ''}" ${attrs}>${text}</button>`;
const sample = (t = 'Sample') => `<span class="sample" title="Made-up data for the demo">${t}</span>`;
const touchOnly = matchMedia('(hover: none)').matches;
const C = { green: '#d2d2d2', blue: '#9c9c9c', purple: '#7e7e7e', red: '#c4c4c4', orange: '#bdbdbd', yellow: '#e2e2e2', gray: '#6a6a6a', pink: '#a8a8a8', teal: '#b5b5b5' };

// ---------- model ----------

const TABS = [
  { id: 'home', icon: 'note', short: 'Playing', title: 'Now Playing' },
  { id: 'today', icon: 'calendar', short: 'Today', title: 'Calendar & Weather' },
  { id: 'shelf', icon: 'tray', short: 'Tray', title: 'File Tray' },
  { id: 'clipboard', icon: 'clipboard', short: 'Clips', title: 'Clipboard' },
  { id: 'timer', icon: 'timer', short: 'Timer', title: 'Timers & Pomodoro' },
  { id: 'mirror', icon: 'webcam', short: 'Mirror', title: 'Mirror' },
  { id: 'devices', icon: 'cpu', short: 'System', title: 'System' },
  { id: 'prompter', icon: 'bubble', short: 'Prompt', title: 'Teleprompter' },
  { id: 'agents', icon: 'sparkles', short: 'Agents', title: 'AI Agents' },
];
const M = { open: false, tab: 'home', pinned: false, inside: false, hover: true, glow: false };

const root = document.documentElement;
const wrap = $('#wrap'), notch = $('#notch'), closedView = $('#closedView'), openView = $('#openView');
const strip = $('#strip'), content = $('#content'), toastEl = $('#toast'), caption = $('#caption');
const CAPTION = caption.textContent;
openView.inert = true;

// Fit the 400 pt panel (plus its flared corners) on narrow screens by scaling the whole notch.
function fit() {
  const s = Math.min(1, (window.innerWidth - 16) / (400 + 18));
  root.style.setProperty('--s', s.toFixed(4));
}
fit();
addEventListener('resize', fit);

// ---------- tab strip ----------

strip.innerHTML = TABS.map(t =>
  `<button class="tabbtn" role="tab" id="tab-${t.id}" data-tab="${t.id}" aria-controls="pane-${t.id}" aria-label="${t.title}" title="${t.title}">${ic(t.icon, 13)}<span class="lbl">${t.short}</span></button>`
).join('') + '<span class="grow"></span>' +
  ib('pin', 10, 'dim', 'Keep open', 'id="pinBtn" aria-pressed="false"') +
  ib('gear', 10, 'dim', 'Settings', 'id="gearBtn"');

strip.addEventListener('click', e => {
  const b = e.target.closest('[data-tab]');
  if (b) setTab(b.dataset.tab);
});
$('#pinBtn').addEventListener('click', () => { M.pinned = !M.pinned; updatePin(); });
$('#gearBtn').addEventListener('click', () => Settings.toggle());

function updatePin() {
  const b = $('#pinBtn');
  b.classList.toggle('pinned', M.pinned);
  b.classList.toggle('dim', !M.pinned);
  b.setAttribute('aria-pressed', String(M.pinned));
  b.querySelector('use').setAttribute('href', '#i-pin');
  b.querySelector('svg').style.fill = M.pinned ? 'currentColor' : 'none';
}

const panes = {};
function setTab(id) {
  const prev = M.tab;
  if (prev !== id) panes[prev]?.hide?.();
  M.tab = id;
  $$('.tabbtn', strip).forEach(b => {
    const on = b.dataset.tab === id;
    b.classList.toggle('sel', on);
    b.setAttribute('aria-selected', String(on));
    b.tabIndex = on ? 0 : -1;
  });
  $$('.tab', content).forEach(p => p.classList.toggle('on', p.dataset.pane === id));
  Settings.close();
  if (M.open) panes[id]?.show?.();
}
function step(d) {
  const i = TABS.findIndex(t => t.id === M.tab);
  setTab(TABS[(i + d + TABS.length) % TABS.length].id);
}

// ---------- open / close ----------

let openT, closeT;
function openPanel(tab) {
  clearTimeout(closeT);
  if (tab) setTab(tab);
  if (M.open) return;
  M.open = true;
  notch.classList.add('open');
  openView.inert = false;
  openView.setAttribute('aria-hidden', 'false');
  closedView.setAttribute('aria-expanded', 'true');
  $('#hint').classList.add('done');
  panes[M.tab]?.show?.();
}
function closePanel() {
  if (!M.open) return;
  M.pinned = false; updatePin();
  // Always reopen on the player, never on whatever list was last left open.
  Player.resetBrowse();
  panes[M.tab]?.hide?.();
  Settings.close();
  const hadFocus = openView.contains(document.activeElement);
  M.open = false;
  notch.classList.remove('open');
  openView.inert = true;
  openView.setAttribute('aria-hidden', 'true');
  closedView.setAttribute('aria-expanded', 'false');
  if (hadFocus) closedView.focus({ preventScroll: true });
}

// Hover, don't click: open after a 0.15 s dwell, close 0.35 s after the pointer leaves.
notch.addEventListener('pointerenter', e => {
  if (e.pointerType !== 'mouse') return;
  M.inside = true;
  clearTimeout(closeT);
  if (!M.open && M.hover) openT = setTimeout(() => openPanel(), 150);
});
notch.addEventListener('pointerleave', e => {
  if (e.pointerType !== 'mouse') return;
  M.inside = false;
  clearTimeout(openT);
  if (M.open && !M.pinned) closeT = setTimeout(closePanel, 350);
});
closedView.addEventListener('click', () => {
  openPanel();
  requestAnimationFrame(() => $('.tabbtn.sel', strip)?.focus({ preventScroll: true }));
});
// Taps outside close it on touch screens (and clicks, when it was opened another way).
document.addEventListener('pointerdown', e => {
  if (!M.open || M.pinned || wrap.contains(e.target) || e.target.closest('.chip')) return;
  closePanel();
});
document.addEventListener('keydown', e => {
  if (!M.open) return;
  const typing = /^(INPUT|TEXTAREA)$/.test(e.target.tagName);
  if (e.key === 'Escape') { closePanel(); e.preventDefault(); }
  else if (!typing && e.key === 'ArrowRight') { step(1); $('.tabbtn.sel', strip)?.focus(); e.preventDefault(); }
  else if (!typing && e.key === 'ArrowLeft') { step(-1); $('.tabbtn.sel', strip)?.focus(); e.preventDefault(); }
});

// ---------- alerts under the notch ----------

let toastT;
function toast(icon, text, tint = '#e0e0e0', secs = 5) {
  // The alert drops down beneath the collapsed notch. If nobody is pointing at an open,
  // unpinned panel it would already have closed in the app, so close it here too.
  if (M.open && !M.pinned && !M.inside) closePanel();
  const html = `<span style="color:${tint}">${ic(icon, 12)}</span><span>${esc(text)}</span>`;
  toastEl.innerHTML = html;
  notch.classList.add('has-toast');
  if (M.open) caption.innerHTML = `<span style="display:inline-flex;gap:6px;align-items:center;color:#e0e0e0">${html}</span>`;
  clearTimeout(toastT);
  toastT = setTimeout(() => { notch.classList.remove('has-toast'); caption.textContent = CAPTION; }, secs * 1000);
}

// A short glass-like chime for timers (the app plays the system "Glass" sound).
let audio;
function primeAudio() {
  try { audio = audio || new (window.AudioContext || window.webkitAudioContext)(); audio.resume(); } catch { /* no audio */ }
}
function chime() {
  if (!audio) return;
  const t = audio.currentTime;
  [[1318.5, 0], [1975.5, 0.09]].forEach(([f, d]) => {
    const o = audio.createOscillator(), g = audio.createGain();
    o.type = 'sine'; o.frequency.value = f;
    g.gain.setValueAtTime(0.0001, t + d);
    g.gain.exponentialRampToValueAtTime(0.18, t + d + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + d + 1.1);
    o.connect(g).connect(audio.destination);
    o.start(t + d); o.stop(t + d + 1.2);
  });
}

// ---------- panes ----------

function pane(id, cls, html) {
  const el = document.createElement('div');
  el.className = `tab ${cls}`;
  el.dataset.pane = id;
  el.id = `pane-${id}`;
  el.setAttribute('role', 'tabpanel');
  el.setAttribute('aria-labelledby', `tab-${id}`);
  el.innerHTML = html;
  content.appendChild(el);
  return el;
}

// ===== Playing =====

const ART = [['#4a4a4a'], ['#5a5a5a'], ['#3a3a3a'], ['#6a6a6a'], ['#444'], ['#555'], ['#333'], ['#666']];
const mk = (name, artist, dur) => ({ name, artist, dur });
const PLAYLISTS = [
  { name: 'Deep Focus', tracks: [mk('Paper Lanterns', 'Mira Okafor', 214), mk('Slow Orbit', 'The Quiet Hours', 247), mk('Glasshouse', 'Lumen Drift', 198), mk('North of Nowhere', 'Halden', 263), mk('Afterimage', 'Sora Vale', 231), mk('Tidewater', 'Kestrel Bay', 205), mk('Low Sun', 'Mira Okafor', 189)] },
  { name: 'Morning Run', tracks: [mk('Starting Gun', 'Neon Parade', 176), mk('Overpass', 'Bright Static', 201), mk('Mile Marker', 'Coastline Club', 188), mk('Second Wind', 'Neon Parade', 194), mk('Pace Setter', 'Volt & Vine', 210)] },
  { name: 'Late Night Drive', tracks: [mk('Sodium Lights', 'Night Ferry', 242), mk('Exit 14', 'Marlow Grey', 225), mk('Rearview', 'The Velvet Hours', 256), mk('Empty Lanes', 'Night Ferry', 233)] },
  { name: 'Study Beats', tracks: [mk('Index Cards', 'lofi kid', 131), mk('Highlighter', 'Paper Planes', 144), mk('Margin Notes', 'lofi kid', 128), mk('Office Hours', 'Desk Plant', 152), mk('Footnote', 'Paper Planes', 139), mk('Library Rain', 'Desk Plant', 161)] },
  { name: 'Road Trip', tracks: [mk('Open Highway', 'Sunset Motel', 219), mk('State Line', 'Copper Canyon', 204), mk('Gas Station Coffee', 'Sunset Motel', 187)] },
  { name: 'Rainy Day', tracks: [mk('Window Seat', 'Ada Linn', 236), mk('Puddles', 'Grey Weather', 198), mk('Umbrella', 'Ada Linn', 211)] },
];
PLAYLISTS.forEach((p, pi) => p.tracks.forEach((t, ti) => { t.art = ART[(pi * 3 + ti) % ART.length]; }));
const LYRICS = ['♪', 'Lights along the water, slow and low', 'I keep the window down to hear it go', 'Every street is humming something new',
  'And I love this part', 'Hold the note a little longer now', 'Turn it up, the city knows the words', '♪'];

const Player = (() => {
  const el = pane('home', 'player-pane', `
    <div class="pv player" style="display:flex;width:100%">
      <div class="p-top">
        <div class="art" id="pArt">${ic('note', 18)}</div>
        <div class="p-meta">
          <div class="p-title ell" id="pTitle"></div>
          <div class="p-artist"><span class="ell" id="pArtist"></span>${sample()}</div>
        </div>
        <div class="wave" id="pWave" aria-hidden="true"><span></span><span></span><span></span><span></span><span></span></div>
      </div>
      <div class="scrub">
        <span class="el" id="pEl">0:00</span>
        <div class="bar" id="pBar" role="slider" tabindex="0" aria-label="Playback position" aria-valuemin="0"><div class="track"><div class="fill" id="pFill"></div></div></div>
        <span class="rem" id="pRem">--:--</span>
      </div>
      <div class="transport">
        <div class="t-side">
          ${ib('listmusic', 12, 'dim', 'Playlists', 'data-a="browse"')}
          ${ib('quote', 12, 'dim', 'Show lyrics', 'data-a="lyrics" id="pLyrBtn"')}
          <span class="grow"></span>
          ${ib('external', 12, 'dim', 'Open the player app', 'data-a="openapp"')}
        </div>
        <div class="t-center">
          ${ib('back', 14, '', 'Previous', 'data-a="prev"')}
          <span class="playbtn">${ib('pause', 20, '', 'Pause', 'data-a="toggle" id="pPlay"')}</span>
          ${ib('fwd', 14, '', 'Next', 'data-a="next"')}
        </div>
      </div>
      <div class="lyric ell" id="pLyric" hidden></div>
    </div>
    <div class="pl" style="display:flex;width:100%" hidden>
      <div class="pl-head" id="plHead"></div>
      <div class="pl-list scroller fade" id="plList"></div>
    </div>`);
  const pv = $('.pv', el), pl = $('.pl', el);
  const S = { list: PLAYLISTS[0].tracks, i: 0, playing: true, pos: 52, lyrics: false, lastLyric: '' };
  const B = { browsing: false, open: null, queueView: false, query: '', shuffle: false, loading: false };
  const queue = [];
  const track = () => S.list[S.i];

  function renderTrack() {
    const t = track();
    $('#pTitle', el).textContent = t.name;
    $('#pArtist', el).textContent = t.artist;
    $('#pArt', el).style.background = t.art[0];
    $('#pBar', el).setAttribute('aria-valuemax', String(t.dur));
    renderPlay(); renderPos();
  }
  function renderPlay() {
    const b = $('#pPlay', el);
    b.querySelector('use').setAttribute('href', S.playing ? '#i-pause' : '#i-play');
    b.setAttribute('aria-label', S.playing ? 'Pause' : 'Play'); b.title = b.getAttribute('aria-label');
  }
  let drag = null;
  function renderPos() {
    const t = track(), pos = drag ?? S.pos, f = Math.min(1, pos / t.dur);
    $('#pFill', el).style.width = `${f * 100}%`;
    $('#pEl', el).textContent = clock(pos);
    $('#pRem', el).textContent = '-' + clock(t.dur - pos);
    $('#pBar', el).setAttribute('aria-valuenow', String(Math.round(pos)));
    $('#pBar', el).setAttribute('aria-valuetext', `${clock(pos)} of ${clock(t.dur)}`);
    if (S.lyrics) {
      const line = LYRICS[Math.floor(pos / 4.5) % LYRICS.length];
      const ly = $('#pLyric', el);
      if (line !== S.lastLyric) {
        S.lastLyric = line;
        ly.classList.add('swap');
        setTimeout(() => { ly.textContent = line; ly.classList.remove('swap'); }, 120);
      }
    }
  }
  function next() {
    if (queue.length) { const q = queue.shift(); S.list = q.list; S.i = q.i; renderBrowse(); }
    else S.i = (S.i + 1) % S.list.length;
    S.pos = 0; S.lastLyric = ''; renderTrack();
  }
  function prev() {
    if (S.pos > 3) S.pos = 0; else { S.i = (S.i - 1 + S.list.length) % S.list.length; S.pos = 0; }
    renderTrack();
  }

  // Scrubber: drag to seek, the bar thickens while dragging.
  const bar = $('#pBar', el);
  const at = e => { const r = bar.getBoundingClientRect(); return Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)) * track().dur; };
  bar.addEventListener('pointerdown', e => { bar.setPointerCapture(e.pointerId); bar.classList.add('drag'); drag = at(e); renderPos(); });
  bar.addEventListener('pointermove', e => { if (drag != null) { drag = at(e); renderPos(); } });
  const endDrag = () => { if (drag != null) { S.pos = drag; drag = null; bar.classList.remove('drag'); renderPos(); } };
  bar.addEventListener('pointerup', endDrag);
  bar.addEventListener('pointercancel', endDrag);
  bar.addEventListener('keydown', e => {
    if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
      S.pos = Math.max(0, Math.min(track().dur - 1, S.pos + (e.key === 'ArrowRight' ? 5 : -5)));
      renderPos(); e.preventDefault(); e.stopPropagation();
    }
  });

  // Waveform: five bars, 3 + 11·|sin(t·speed + phase)|, refreshed every 0.12 s while playing.
  const bars = $$('#pWave span', el);
  setInterval(() => {
    if (!M.open || M.tab !== 'home' || B.browsing) return;
    const t = performance.now() / 1000;
    bars.forEach((b, i) => { b.style.height = (S.playing ? 3 + 11 * Math.abs(Math.sin(t * (3.1 + i * 0.9) + i * 1.7)) : 3) + 'px'; });
  }, 120);

  let last = performance.now();
  setInterval(() => {
    const now = performance.now(), dt = (now - last) / 1000; last = now;
    if (!S.playing || drag != null) return;
    S.pos += dt;
    if (S.pos >= track().dur) next();
    else if (M.open && M.tab === 'home') renderPos();
  }, 250);

  // ---- playlists, tracks and queue: three screens, one chrome ----
  const screen = () => B.queueView ? 'queue' : (B.open == null ? 'playlists' : 'tracks');
  function renderBrowse() {
    if (!B.browsing) return;
    const sc = screen(), head = $('#plHead', el);
    const badge = queue.length && sc !== 'queue'
      ? `<button class="qbadge" data-a="showqueue" title="${queue.length} queued" aria-label="${queue.length} queued">${ic('append', 10)}${queue.length}</button>` : '';
    const back = ib('left', 11, 'dim55', sc === 'queue' ? 'Back' : sc === 'tracks' ? 'All playlists' : 'Back to the player', 'data-a="back"');
    if (sc === 'queue') {
      head.innerHTML = `${back}<span class="h">Up next</span><span class="n">${queue.length}</span><span class="grow"></span>` +
        (queue.length ? ib('play', 11, '', 'Play the next one now', 'data-a="qplay" style="color:rgba(255,255,255,.6)"') + ib('trash', 11, 'dim35', 'Clear the queue', 'data-a="qclear"') : '');
    } else {
      const ph = B.open != null ? `Search ${PLAYLISTS[B.open].name}` : 'Search playlists';
      const tools = B.open != null
        ? ib('shuffle', 11, '', 'Shuffle this playlist', 'data-a="shuffleplay" style="color:rgba(255,255,255,.6)"')
        : ib('shuffle', 11, B.shuffle ? 'on' : 'dim35', B.shuffle ? 'Playlists start shuffled' : 'Playlists start in order', 'data-a="shufflepref"') +
          ib('refresh', 10, 'dim35', 'Reload library', 'data-a="reload"');
      head.innerHTML = `${back}<label class="search">${ic('search', 10)}<input id="plQ" placeholder="${esc(ph)}" aria-label="${esc(ph)}" value="${esc(B.query)}" autocomplete="off"></label>${tools}${badge}`;
      $('#plQ', el).addEventListener('input', e => { B.query = e.target.value; renderList(); });
    }
    renderList();
  }
  const row = (icon, title, sub, trailing, a, i, acc) => {
    const hov = icon === 'play' ? '' : ic('play', 10, 'hov');
    const accHtml = acc ? `<button class="acc" data-a="${acc.a}" data-i="${i}" aria-label="${acc.label}" title="${acc.label}">${ic(acc.icon, 11)}</button>` : '';
    return `<div class="lrow" role="button" tabindex="0" data-a="${a}" data-i="${i}">
      <span class="li">${ic(icon, 10, icon === 'play' ? '' : 'rest')}${hov}</span>
      <span class="tt ell">${esc(title)}</span>${sub ? `<span class="st ell">${esc(sub)}</span>` : ''}
      ${trailing ? `<span class="tr">${trailing}</span>` : ''}${accHtml}</div>`;
  };
  const centred = t => `<div class="centred">${esc(t)}</div>`;
  function renderList() {
    const list = $('#plList', el), q = B.query.trim().toLowerCase(), sc = screen();
    if (B.loading) { list.innerHTML = centred('Reading your library…'); return; }
    if (sc === 'playlists') {
      const items = PLAYLISTS.map((p, i) => ({ p, i })).filter(x => !q || x.p.name.toLowerCase().includes(q));
      list.innerHTML = items.length ? items.map(x => row('listmusic', x.p.name, '', x.p.tracks.length, 'openpl', x.i)).join('')
        : centred(`Nothing matches “${B.query}”.`);
    } else if (sc === 'tracks') {
      const p = PLAYLISTS[B.open];
      const items = p.tracks.map((t, i) => ({ t, i })).filter(x => !q || x.t.name.toLowerCase().includes(q) || x.t.artist.toLowerCase().includes(q));
      list.innerHTML = items.length ? items.map(x => row('play', x.t.name, x.t.artist, '', 'playtrack', x.i, { a: 'enqueue', icon: 'plus', label: 'Add to the queue' })).join('')
        : centred(`Nothing matches “${B.query}”.`);
    } else {
      list.innerHTML = queue.length ? queue.map((x, i) => row('note', x.list[x.i].name, x.list[x.i].artist, '', 'qplayone', i, { a: 'qremove', icon: 'x', label: 'Remove from the queue' })).join('')
        : centred('Nothing queued. Add tracks with the + beside them.');
    }
  }
  function setBrowsing(on) {
    B.browsing = on;
    pv.hidden = on; pl.hidden = !on;
    if (on) renderBrowse();
    else { B.open = null; B.queueView = false; B.query = ''; renderTrack(); }
  }
  function play(list, i) { S.list = list; S.i = i; S.pos = 0; S.playing = true; S.lastLyric = ''; renderTrack(); setBrowsing(false); }

  el.addEventListener('click', e => {
    const b = e.target.closest('[data-a]');
    if (!b) return;
    const i = Number(b.dataset.i);
    switch (b.dataset.a) {
      case 'toggle': S.playing = !S.playing; renderPlay(); break;
      case 'next': next(); break;
      case 'prev': prev(); break;
      case 'browse': setBrowsing(true); setTimeout(() => $('#plQ', el)?.focus({ preventScroll: true }), 50); break;
      case 'openapp': toastInPanel('Opens Music or Spotify on a Mac'); break;
      case 'lyrics': {
        S.lyrics = !S.lyrics; S.lastLyric = '';
        const lb = $('#pLyrBtn', el);
        lb.querySelector('use').setAttribute('href', S.lyrics ? '#i-quotefill' : '#i-quote');
        lb.classList.toggle('dim', !S.lyrics); lb.classList.toggle('on', S.lyrics);
        lb.title = S.lyrics ? 'Hide lyrics' : 'Show lyrics (sample lyrics in the demo)';
        $('#pLyric', el).hidden = !S.lyrics; renderPos(); break;
      }
      case 'back':
        B.query = '';
        if (B.queueView) B.queueView = false; else if (B.open != null) B.open = null; else { setBrowsing(false); break; }
        renderBrowse(); break;
      case 'openpl': {
        B.open = i; B.query = '';
        if (B.shuffle) { const p = PLAYLISTS[i]; play(shuffled(p.tracks), 0); B.open = null; break; }
        renderBrowse(); break;
      }
      case 'playtrack': play(PLAYLISTS[B.open].tracks, i); B.open = null; B.query = ''; break;
      case 'enqueue': queue.push({ list: PLAYLISTS[B.open].tracks, i }); renderBrowse(); break;
      case 'shuffleplay': play(shuffled(PLAYLISTS[B.open].tracks), 0); B.open = null; break;
      case 'shufflepref': B.shuffle = !B.shuffle; renderBrowse(); break;
      case 'reload': B.loading = true; renderList(); setTimeout(() => { B.loading = false; renderList(); }, 450); break;
      case 'showqueue': B.queueView = true; B.query = ''; renderBrowse(); break;
      case 'qplay': next(); setBrowsing(false); break;
      case 'qplayone': { const [x] = queue.splice(i, 1); play(x.list, x.i); B.queueView = false; break; }
      case 'qremove': queue.splice(i, 1); renderBrowse(); break;
      case 'qclear': queue.length = 0; renderBrowse(); break;
    }
  });
  el.addEventListener('keydown', e => {
    if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('.lrow')) { e.preventDefault(); e.target.click(); }
  });
  const shuffled = a => { const b = a.slice(); for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; } return b; };

  renderTrack();
  return {
    show() { renderTrack(); if (B.browsing) renderBrowse(); },
    resetBrowse() { B.open = null; B.queueView = false; B.query = ''; setBrowsing(false); },
    browse() { setBrowsing(true); },
  };
})();
panes.home = Player;

// A short status line under the panel, for actions the browser cannot do.
let capT;
function toastInPanel(text) {
  caption.textContent = text;
  clearTimeout(capT);
  capT = setTimeout(() => { caption.textContent = CAPTION; }, 2600);
}

// ===== Today =====

const Today = (() => {
  const el = pane('today', 'today', `
    <div class="t-head">
      <span class="t-date" id="tDate"></span>${sample()}
      <span class="grow"></span>
      <span class="t-wx" title="Partly sunny · H 66° L 54°">${ic('sun', 13)}<span>61° San Francisco</span></span>
    </div>
    <div class="events scroller" id="tEvents"></div>`);
  function render() {
    const now = new Date();
    $('#tDate', el).textContent = now.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
    const base = new Date(now); base.setMinutes(now.getMinutes() < 30 ? 30 : 60, 0, 0);
    const at = (h, m = 0) => new Date(base.getTime() + (h * 60 + m) * 60000);
    const tomorrow = new Date(now); tomorrow.setDate(now.getDate() + 1); tomorrow.setHours(0, 0, 0, 0);
    const tAt = (h, m = 0) => { const d = new Date(tomorrow); d.setHours(h, m); return d; };
    const evs = [
      { title: 'Team standup', start: at(0), end: at(0, 15), color: C.blue },
      { title: 'Design review', start: at(2), end: at(2, 30), color: C.purple },
      { title: 'Gym', start: at(4), end: at(5), color: C.green },
      { title: 'Hackathon', start: tomorrow, allDay: true, color: C.orange },
      { title: 'Dentist', start: tAt(9), end: tAt(9, 45), color: C.red },
    ].sort((a, b) => a.start - b.start);
    const fmt = d => d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
    const sameDay = (a, b) => a.toDateString() === b.toDateString();
    $('#tEvents', el).innerHTML = evs.map(e => {
      const day = sameDay(e.start, now) ? '' : 'Tomorrow · ';
      const when = day + (e.allDay ? 'All day' : `${fmt(e.start)} – ${fmt(e.end)}`);
      return `<div class="ev"><span class="cap" style="background:${e.color}"></span><div style="min-width:0"><div class="et ell">${esc(e.title)}</div><div class="ew">${when}</div></div></div>`;
    }).join('');
  }
  return { show: render };
})();
panes.today = Today;

// ===== Tray =====

const Tray = (() => {
  const el = pane('shelf', 'shelf', `
    <button class="airdrop" id="airdrop" title="Drop files to AirDrop them, or click to AirDrop everything in the tray">
      ${ic('airdrop', 19)}<span class="a1">AirDrop</span><span class="a2">Drop to send</span>
    </button>
    <div class="tray-r">
      <div class="tray-h"><span class="h" id="trayH">Tray</span><span class="pstat" id="trayBusy"></span><span class="grow"></span><span id="trayBtns"></span></div>
      <div id="trayBody" style="flex:1;display:flex;min-height:0"></div>
    </div>`);
  const items = [];
  let busyT;
  function busy(text) {
    const b = $('#trayBusy', el); b.textContent = text;
    clearTimeout(busyT); busyT = setTimeout(() => { b.textContent = ''; }, 2600);
  }
  const extColor = ext => ({ pdf: '#8a8a8a', zip: '#6a6a6a', png: '#777', jpg: '#777', jpeg: '#777', gif: '#777', heic: '#777', mp3: '#5e5e5e', wav: '#5e5e5e', mov: '#6e6e6e', mp4: '#6e6e6e' }[ext] || '#555');
  function render() {
    $('#trayH', el).textContent = items.length ? `Tray · ${items.length}` : 'Tray';
    $('#trayBtns', el).innerHTML = (items.length ? pill('Clear', 'data-a="clear"') : '');
    const body = $('#trayBody', el);
    if (!items.length) {
      body.innerHTML = `<div class="tray-empty">${ic('traydown', 22)}<span>Drag files onto the notch</span><button class="linkish" data-a="pick">or choose files</button></div>`;
      return;
    }
    body.innerHTML = `<div class="tray-items">${items.map((f, i) => {
      const ext = (f.name.split('.').pop() || '').toLowerCase().slice(0, 4);
      const thumb = f.img ? `<img src="${f.url}" alt="">` : `<span class="doc"><b style="background:${extColor(ext)}">${esc(ext || 'file')}</b></span>`;
      return `<div class="titem" role="button" tabindex="0" data-a="open" data-i="${i}" title="${esc(f.name)} · ${fmtSize(f.size)}. Click to open in a new tab.">
        <span class="thumb">${thumb}</span><span class="nm">${esc(f.name)}</span>
        <button class="rm" data-a="remove" data-i="${i}" aria-label="Remove ${esc(f.name)} from the tray" title="Remove from tray">${ic('xcircle', 15)}</button>
      </div>`;
    }).join('')}</div>`;
  }
  const fmtSize = b => b < 1024 ? `${b} bytes` : b < 1048576 ? `${(b / 1024).toFixed(0)} KB` : `${(b / 1048576).toFixed(1)} MB`;
  function add(files) {
    for (const f of files) {
      if (items.some(x => x.name === f.name && x.size === f.size)) continue;
      items.push({ name: f.name, size: f.size, url: URL.createObjectURL(f), img: /^image\//.test(f.type) });
    }
    render();
  }
  el.addEventListener('click', e => {
    const b = e.target.closest('[data-a]');
    if (b) {
      const i = Number(b.dataset.i);
      if (b.dataset.a === 'remove') { URL.revokeObjectURL(items[i].url); items.splice(i, 1); render(); }
      else if (b.dataset.a === 'open') window.open(items[i].url, '_blank', 'noopener');
      else if (b.dataset.a === 'clear') { items.forEach(x => URL.revokeObjectURL(x.url)); items.length = 0; render(); }
      else if (b.dataset.a === 'pick') $('#filePick').click();
      return;
    }
    if (e.target.closest('#airdrop')) busy(items.length ? 'AirDrop is in the Mac app' : 'Nothing to send');
  });
  el.addEventListener('keydown', e => {
    if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('.titem')) { e.preventDefault(); e.target.click(); }
  });
  const ad = $('#airdrop', el);
  ad.addEventListener('dragover', e => { e.preventDefault(); ad.classList.add('target'); });
  ad.addEventListener('dragleave', () => ad.classList.remove('target'));
  ad.addEventListener('drop', e => { ad.classList.remove('target'); });
  $('#filePick').addEventListener('change', e => { add(e.target.files); e.target.value = ''; openPanel('shelf'); });
  render();
  return { add, busy };
})();
panes.shelf = Tray;

// Dropping files anywhere on the notch opens the tray and parks them there (in this page only).
const hasFiles = e => [...(e.dataTransfer?.types || [])].includes('Files');
let dragDepth = 0;
document.addEventListener('dragover', e => { if (hasFiles(e)) e.preventDefault(); });
document.addEventListener('drop', e => { if (hasFiles(e)) e.preventDefault(); });
notch.addEventListener('dragenter', e => {
  if (!hasFiles(e)) return;
  e.preventDefault();
  dragDepth++;
  clearTimeout(closeT);
  notch.classList.add('drop');
  if (!M.open) openPanel('shelf');
});
notch.addEventListener('dragleave', () => {
  dragDepth = Math.max(0, dragDepth - 1);
  if (dragDepth === 0) {
    notch.classList.remove('drop');
    if (M.open && !M.pinned) closeT = setTimeout(closePanel, 350);
  }
});
notch.addEventListener('drop', e => {
  if (!hasFiles(e)) return;
  e.preventDefault();
  dragDepth = 0;
  notch.classList.remove('drop');
  clearTimeout(closeT);
  const files = e.dataTransfer.files;
  if (e.target.closest('#airdrop')) { setTab('shelf'); Tray.busy(`AirDrop is in the Mac app`); return; }
  setTab('shelf');
  Tray.add(files);
});

// ===== Clips =====

const Clips = (() => {
  const el = pane('clipboard', 'clips', `
    <div class="clips-h">
      <label class="search">${ic('search', 12)}<input id="cQ" placeholder="Search" aria-label="Search clipboard history" autocomplete="off"></label>
      ${sample()}
      ${ib('record', 13, 'rec', 'Recording copies. Click to pause.', 'data-a="rec" id="cRec"')}
      ${ib('trash', 12, '', 'Clear history', 'data-a="clear" style="color:rgba(255,255,255,.5)"')}
    </div>
    <div class="clist scroller" id="cList"></div>`);
  const min = 60000;
  let id = 0;
  const clips = [
    { text: 'npm run build && npm run preview', t: Date.now() - 2 * min },
    { text: 'https://github.com/VikramMenon09/Topside', t: Date.now() - 5 * min },
    { text: 'Meeting moved to 3:30, same room', t: Date.now() - 12 * min },
    { image: '#4a4a4a', t: Date.now() - 26 * min },
    { text: '#8A8A8A', t: Date.now() - 41 * min },
    { text: "SELECT id, total FROM orders WHERE status = 'open';", t: Date.now() - 95 * min },
    { text: 'Thanks! I\'ll take a look tonight and get back to you.', t: Date.now() - 3 * 60 * min },
    { text: 'git switch -c web-demo', t: Date.now() - 5 * 60 * min },
  ].map(c => ({ ...c, id: ++id }));
  let recording = true, copied = null, query = '';

  function render() {
    const q = query.trim().toLowerCase();
    const res = q ? clips.filter(c => (c.text ?? 'image').toLowerCase().includes(q)) : clips;
    const list = $('#cList', el);
    if (!res.length) {
      list.innerHTML = `<div class="centred" style="font-size:12px">${clips.length ? 'No matches' : 'Things you copy will show up here'}</div>`;
      return;
    }
    list.innerHTML = res.map(c => `
      <div class="crow" role="button" tabindex="0" data-a="copy" data-id="${c.id}" title="Click to copy">
        ${c.image ? `<span class="img" style="background:${c.image}"></span><span class="ct">Image</span>` : `<span class="ct ell">${esc(c.text.trim())}</span>`}
        <span class="ago${copied === c.id ? ' ok' : ''}">${copied === c.id ? 'Copied' : ago(c.t)}</span>
        ${ib('x', 9, 'dim', 'Remove', `data-a="remove" data-id="${c.id}"`)}
      </div>`).join('');
  }
  function renderRec() {
    const b = $('#cRec', el);
    b.querySelector('use').setAttribute('href', recording ? '#i-record' : '#i-pausecircle');
    b.classList.toggle('rec', recording); b.classList.toggle('dim55', !recording);
    const l = recording ? 'Recording copies. Click to pause.' : 'Paused. Click to record copies.';
    b.title = l; b.setAttribute('aria-label', l);
  }
  $('#cQ', el).addEventListener('input', e => { query = e.target.value; render(); });
  el.addEventListener('click', e => {
    const b = e.target.closest('[data-a]');
    if (!b) return;
    const cid = Number(b.dataset.id);
    if (b.dataset.a === 'remove') { const i = clips.findIndex(c => c.id === cid); if (i >= 0) clips.splice(i, 1); render(); }
    else if (b.dataset.a === 'clear') { clips.length = 0; render(); }
    else if (b.dataset.a === 'rec') { recording = !recording; renderRec(); }
    else if (b.dataset.a === 'copy') {
      const c = clips.find(x => x.id === cid);
      if (c?.text && navigator.clipboard) navigator.clipboard.writeText(c.text).catch(() => {});
      copied = cid; render();
      setTimeout(() => { if (copied === cid) { copied = null; render(); } }, 1200);
    }
  });
  el.addEventListener('keydown', e => {
    if ((e.key === 'Enter' || e.key === ' ') && e.target.matches('.crow')) { e.preventDefault(); e.target.click(); }
  });
  // Anything you copy on this page lands in the history, like the app's pasteboard watcher.
  document.addEventListener('copy', e => {
    if (!recording) return;
    let text = '';
    const t = e.target;
    if (t && /^(INPUT|TEXTAREA)$/.test(t.tagName) && typeof t.selectionStart === 'number') text = t.value.slice(t.selectionStart, t.selectionEnd);
    else text = String(document.getSelection() || '');
    text = text.trim();
    if (!text) return;
    const dup = clips.findIndex(c => c.text === text);
    if (dup >= 0) clips.splice(dup, 1);
    clips.unshift({ id: ++id, text, t: Date.now() });
    if (clips.length > 50) clips.pop();
    if (M.open && M.tab === 'clipboard') render();
    else toast('clipboard', 'Copied to Clips', '#e0e0e0', 2.5);
  });
  render();
  return { show: render };
})();
panes.clipboard = Clips;

// ===== Timer =====

const Timer = (() => {
  const CIRC = 2 * Math.PI * 45.5;
  const el = pane('timer', 'timer', `
    <div class="ring" role="timer" aria-live="off">
      <svg width="96" height="96" viewBox="0 0 96 96" aria-hidden="true">
        <circle class="bg" cx="48" cy="48" r="45.5" fill="none" stroke-width="5"/>
        <circle class="fg" id="tmFg" cx="48" cy="48" r="45.5" fill="none" stroke-width="5" stroke-linecap="round" stroke-dasharray="${CIRC}" stroke-dashoffset="${CIRC}" opacity="0"/>
      </svg>
      <div class="ring-txt"><span class="tm" id="tmT">0:00</span><span class="tl" id="tmL">Ready</span></div>
    </div>
    <div class="t-ctrl" id="tmCtrl"></div>`);
  const T = { end: null, paused: null, total: 0, label: 'Timer', pomodoro: false, phase: 'Focus', cycles: 0, custom: 20 };
  const WORK = 25 * 60, REST = 5 * 60;
  const active = () => T.end != null || T.paused != null;
  const remaining = () => T.paused != null ? T.paused : T.end != null ? Math.max(0, (T.end - Date.now()) / 1000) : 0;

  function renderCtrl() {
    const c = $('#tmCtrl', el);
    if (active()) {
      c.innerHTML = (T.pomodoro ? `<span class="t-sub">Pomodoro · ${T.cycles} finished</span>` : '') +
        `<div class="t-row g6">${pill(T.paused != null ? 'Resume' : 'Pause', 'data-a="pause"', true)}${pill('Stop', 'data-a="stop"')}</div>`;
    } else {
      c.innerHTML = `<div class="t-row">${[5, 10, 15, 30].map(m => pill(`${m} m`, `data-a="preset" data-m="${m}"`)).join('')}</div>
        <div class="t-row g6"><span class="stepper-l" id="tmCustom">${T.custom} min</span>
          <span class="stepper"><button data-a="inc" aria-label="One minute more">${ic('up', 9)}</button><button data-a="dec" aria-label="One minute less">${ic('down', 9)}</button></span>
          ${pill('Start', 'data-a="custom"', true)}</div>
        ${pill('Start Pomodoro', 'data-a="pomodoro"')}`;
    }
  }
  function renderRing() {
    const r = remaining(), f = T.total > 0 && active() ? r / T.total : 0;
    const fg = $('#tmFg', el);
    fg.setAttribute('stroke-dashoffset', String(CIRC * (1 - f)));
    fg.setAttribute('opacity', f > 0 ? '1' : '0');
    $('#tmT', el).textContent = active() ? clock(r) : '0:00';
    $('#tmL', el).textContent = active() ? T.label : 'Ready';
  }
  function run(sec, name) { T.total = sec; T.label = name; T.paused = null; T.end = Date.now() + sec * 1000; }
  function begin(sec, label) { primeAudio(); T.pomodoro = false; run(sec, label); renderCtrl(); renderRing(); }
  function pomodoro() { primeAudio(); T.pomodoro = true; T.phase = 'Focus'; T.cycles = 0; run(WORK, 'Focus'); renderCtrl(); renderRing(); }
  function finish() {
    chime();
    if (T.pomodoro) {
      if (T.phase === 'Focus') { T.cycles++; T.phase = 'Break'; toast('cup', 'Break time', C.green, 5); run(REST, 'Break'); }
      else { T.phase = 'Focus'; toast('bolt', 'Focus time', C.orange, 5); run(WORK, 'Focus'); }
    } else {
      const name = T.label; T.end = null;
      toast('bell', `${name} done`, C.orange, 6);
    }
    renderCtrl(); renderRing();
  }
  setInterval(() => {
    if (T.end != null && Date.now() >= T.end) finish();
    if (M.open && M.tab === 'timer') renderRing();
  }, 250);
  el.addEventListener('click', e => {
    const b = e.target.closest('[data-a]');
    if (!b) return;
    switch (b.dataset.a) {
      case 'preset': begin(Number(b.dataset.m) * 60, `${b.dataset.m} min`); break;
      case 'inc': T.custom = Math.min(600, T.custom + 1); $('#tmCustom', el).textContent = `${T.custom} min`; break;
      case 'dec': T.custom = Math.max(1, T.custom - 1); $('#tmCustom', el).textContent = `${T.custom} min`; break;
      case 'custom': begin(T.custom * 60, `${T.custom} min`); break;
      case 'pomodoro': pomodoro(); break;
      case 'pause':
        if (T.paused != null) { T.end = Date.now() + T.paused * 1000; T.paused = null; }
        else if (T.end != null) { T.paused = Math.max(0, (T.end - Date.now()) / 1000); T.end = null; }
        renderCtrl(); renderRing(); break;
      case 'stop': T.end = null; T.paused = null; T.pomodoro = false; renderCtrl(); renderRing(); break;
    }
  });
  renderCtrl();
  return { show() { renderCtrl(); renderRing(); }, begin, pomodoro };
})();
panes.timer = Timer;

// ===== Mirror =====

const Mirror = (() => {
  const el = pane('mirror', 'mirror', '');
  let stream = null, state = 'idle'; // idle | starting | live | denied | none
  function render() {
    if (state === 'live') {
      el.innerHTML = `<div class="live"><video id="mVid" autoplay playsinline muted aria-label="Your camera, mirrored"></video>
        <span class="off">${ib('x', 9, '', 'Turn off camera', 'data-a="off" style="background:rgba(0,0,0,.45)"')}</span></div>`;
      $('#mVid', el).srcObject = stream;
      return;
    }
    const msg = {
      idle: 'Check how you look before a call<small>The camera only turns on when you click, and the video never leaves this page.</small>',
      starting: 'Waiting for camera permission…',
      denied: 'Camera access is off for this page. Allow it in your browser\'s site settings, then try again.',
      none: 'No camera is available here.',
    }[state];
    el.innerHTML = `${ic('webcam', 30, 'ph-ic')}<div class="msg">${msg}</div>` +
      (state === 'idle' || state === 'denied' || state === 'none' ? `<button class="bordered" data-a="on">Turn on camera</button>` : '');
  }
  async function start() {
    if (!navigator.mediaDevices?.getUserMedia) { state = 'none'; render(); return; }
    state = 'starting'; render();
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'user', width: { ideal: 640 } }, audio: false });
      if (!M.open || M.tab !== 'mirror') { stop(); return; }
      state = 'live';
    } catch (err) {
      state = err && (err.name === 'NotAllowedError' || err.name === 'SecurityError') ? 'denied' : 'none';
    }
    render();
  }
  function stop() {
    stream?.getTracks().forEach(t => t.stop());
    stream = null;
    if (state === 'live' || state === 'starting') state = 'idle';
    render();
  }
  el.addEventListener('click', e => {
    const b = e.target.closest('[data-a]');
    if (b?.dataset.a === 'on') start();
    else if (b?.dataset.a === 'off') stop();
  });
  render();
  // Like the app, the camera runs only while Mirror is on screen.
  return { show() {}, hide: stop };
})();
panes.mirror = Mirror;

// ===== System =====

const System = (() => {
  const el = pane('devices', 'sys', '');
  const S = { battery: 82, plugged: true, cpu: 0.18, mem: 0.62 };
  const gauge = (icon, name, v, text, color) => `
    <div class="g"><span class="gi">${ic(icon, 13)}</span><span class="gn">${name}</span>
      <span class="gb"><span class="gf" style="width:${Math.min(100, Math.max(2, v * 100))}%;background:${color}"></span></span>
      <span class="gv">${text}</span></div>`;
  function render() {
    el.innerHTML =
      gauge('battery', 'Battery', S.battery / 100, `${S.battery}%${S.plugged ? `<span style="color:${C.yellow}">${ic('bolt', 10)}</span>` : ''}`, S.battery <= 15 ? C.red : C.green) +
      gauge('cpu', 'CPU', S.cpu, `${Math.round(S.cpu * 100)}%`, C.blue) +
      gauge('memory', 'Memory', S.mem, `${Math.round(S.mem * 100)}%`, C.purple) +
      `<div class="g"><span class="gi">${ic('drive', 13)}</span><span class="gn" style="width:auto">Storage free</span>${sample('Sample readings')}<span class="grow"></span><span class="gv" style="width:auto">212.4 GB</span></div>`;
  }
  function update() {
    // Gauges move like a live machine; the values themselves are made up.
    const nudge = (v, lo, hi, amt) => Math.min(hi, Math.max(lo, v + (Math.random() - 0.5) * amt));
    S.cpu = nudge(S.cpu, 0.04, 0.72, 0.18);
    S.mem = nudge(S.mem, 0.52, 0.74, 0.04);
    if (Math.random() < 0.15 && S.battery < 100) S.battery++;
    const [b, c, m] = $$('.gf', el);
    if (!b) return render();
    c.style.width = `${S.cpu * 100}%`; m.style.width = `${S.mem * 100}%`; b.style.width = `${S.battery}%`;
    const vals = $$('.gv', el);
    vals[1].textContent = `${Math.round(S.cpu * 100)}%`; vals[2].textContent = `${Math.round(S.mem * 100)}%`;
    vals[0].firstChild.textContent = `${S.battery}%`;
  }
  setInterval(() => { if (M.open && M.tab === 'devices') update(); }, 2000);
  render();
  return { show() { render(); } };
})();
panes.devices = System;

// ===== Prompt =====

const Prompter = (() => {
  const PER = 6;
  const el = pane('prompter', 'prompt-pane', `
    <div class="prompt pe" style="display:flex;width:100%">
      <div class="p-card"><textarea id="prScript" aria-label="Teleprompter script" spellcheck="false">Paste your script here. Press play and it scrolls right under the camera, so you keep eye contact while you read. Turn on voice follow and it keeps pace with you as you speak.</textarea></div>
      <div class="p-side">
        <span class="h">Teleprompter</span>
        <div class="p-wpm"><span id="prWpmL">140 words/min</span><input type="range" id="prWpm" min="60" max="260" step="10" value="140" aria-label="Words per minute"></div>
        ${pill('Start', 'data-a="start"', true)}
        ${pill('Follow my voice', 'data-a="voice"')}
      </div>
    </div>
    <div class="prun pr" style="display:flex;width:100%" hidden>
      <div class="plines" id="prLines" aria-live="off"></div>
      <div class="pctl">
        ${ib('up', 10, '', 'Back a line', 'data-a="up"')}
        ${ib('down', 10, '', 'Forward a line', 'data-a="down"')}
        <span class="pstat" id="prStat"></span>
        <span class="grow"></span>
        ${pill('Stop', 'data-a="stop"')}
      </div>
    </div>`);
  const P = { words: [], norm: [], index: 0, running: false, voice: false, wpm: 140, timer: null, rec: null, line: -1 };
  const norm = s => s.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
  const wpmIn = $('#prWpm', el);
  const setP = () => wpmIn.style.setProperty('--p', `${(P.wpm - 60) / 200 * 100}%`);
  wpmIn.addEventListener('input', () => { P.wpm = Number(wpmIn.value); $('#prWpmL', el).textContent = `${P.wpm} words/min`; setP(); });
  setP();

  function status(text, voice) {
    const s = $('#prStat', el);
    s.className = 'pstat' + (voice ? ' voice' : '');
    s.innerHTML = voice ? `${ic('mic', 10)}${esc(text || 'Following your voice')}` : esc(text);
  }
  function buildLines() {
    const lines = [];
    for (let i = 0; i < P.words.length; i += PER) lines.push(P.words.slice(i, i + PER));
    $('#prLines', el).innerHTML = lines.map((l, li) =>
      `<div class="pline" data-l="${li}">${l.map((w, j) => `<span class="w" data-w="${li * PER + j}">${esc(w)} </span>`).join('')}</div>`
    ).join('') + '<div style="height:70px"></div>';
  }
  function paint() {
    $$('.w', el).forEach(w => w.classList.toggle('spoken', Number(w.dataset.w) < P.index));
    const line = Math.floor(P.index / PER);
    if (line !== P.line) { P.line = line; scrollToLine(line); }
  }
  let anim;
  function scrollToLine(li) {
    const box = $('#prLines', el), target = $(`.pline[data-l="${li}"]`, el);
    if (!target) return;
    const from = box.scrollTop, to = target.offsetTop - box.offsetTop, t0 = performance.now(), dur = 350;
    cancelAnimationFrame(anim);
    const ease = x => x < .5 ? 2 * x * x : 1 - Math.pow(-2 * x + 2, 2) / 2;
    const tick = now => {
      const k = Math.min(1, (now - t0) / dur);
      box.scrollTop = from + (to - from) * ease(k);
      if (k < 1) anim = requestAnimationFrame(tick);
    };
    anim = requestAnimationFrame(tick);
  }
  function start(useVoice) {
    P.words = $('#prScript', el).value.split(/\s+/).filter(Boolean);
    P.norm = P.words.map(norm);
    if (!P.words.length) return;
    P.index = 0; P.line = -1; P.running = true; P.voice = useVoice;
    $('.pe', el).hidden = true; $('.pr', el).hidden = false;
    buildLines(); $('#prLines', el).scrollTop = 0; paint(); status('');
    if (useVoice) startVoice(); else startClock();
  }
  function startClock() {
    clearInterval(P.timer);
    P.timer = setInterval(() => {
      if (P.index < P.words.length - 1) { P.index++; paint(); } else stop();
    }, 60000 / Math.max(40, P.wpm));
  }
  function startVoice() {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SR) { P.voice = false; status('Voice follow needs Chrome or Safari, so it scrolls on a clock'); startClock(); return; }
    const rec = new SR();
    rec.continuous = true; rec.interimResults = true; rec.lang = navigator.language || 'en-US';
    rec.onresult = e => {
      let heard = '';
      for (let i = e.resultIndex; i < e.results.length; i++) heard += ' ' + e.results[i][0].transcript;
      const words = heard.split(/\s+/).map(norm).filter(Boolean).slice(-4);
      // Move to the furthest of the last few heard words found a little ahead of where we are.
      for (const w of words) {
        const hit = P.norm.indexOf(w, P.index);
        if (hit >= 0 && hit - P.index <= 12) P.index = Math.min(P.words.length, hit + 1);
      }
      paint();
      if (P.index >= P.words.length) stop();
    };
    rec.onerror = e => {
      if (e.error === 'not-allowed' || e.error === 'service-not-allowed') { P.voice = false; status('Microphone is off, so it scrolls on a clock'); P.rec = null; startClock(); }
    };
    rec.onend = () => { if (P.running && P.voice && P.rec === rec) { try { rec.start(); } catch { /* already started */ } } };
    P.rec = rec;
    try { rec.start(); status('', true); } catch { P.voice = false; startClock(); }
  }
  function stop() {
    P.running = false;
    clearInterval(P.timer); P.timer = null;
    const r = P.rec; P.rec = null;
    try { r?.stop(); } catch { /* ignore */ }
    $('.pe', el).hidden = false; $('.pr', el).hidden = true;
  }
  el.addEventListener('click', e => {
    const b = e.target.closest('[data-a]');
    if (!b) return;
    switch (b.dataset.a) {
      case 'start': start(false); break;
      case 'voice': start(true); break;
      case 'stop': stop(); break;
      case 'up': P.index = Math.max(0, Math.min(P.words.length - 1, P.index - PER)); paint(); break;
      case 'down': P.index = Math.max(0, Math.min(P.words.length - 1, P.index + PER)); paint(); break;
    }
  });
  return { show() {}, start };
})();
panes.prompter = Prompter;

// ===== Agents =====

const Agents = (() => {
  const el = pane('agents', 'agents', `
    <div class="ag-h">Recent sessions ${sample()}<span class="grow"></span></div>
    <div class="alist scroller" id="aList"></div>`);
  const STATE = { working: ['Working', C.green], tool: ['Tool running', C.yellow], waiting: ['Waiting', C.orange], idle: ['Idle', C.gray] };
  const now = Date.now(), m = 60000;
  const sessions = [
    { project: 'my-api', tool: 'Claude', state: 'tool', snippet: 'Edit: src/routes/users.ts', t: now - 20000,
      script: [['working', 'Reading src/routes/users.ts'], ['tool', 'Edit: src/routes/users.ts'], ['tool', 'Bash: npm test -- users'], ['working', 'All 24 tests pass. Updating the docs.'], ['tool', 'Edit: README.md']] },
    { project: 'ios-widget', tool: 'Codex', state: 'working', snippet: 'Reading Sources/Widget/Timeline.swift', t: now - 60000,
      script: [['working', 'Reading Sources/Widget/Timeline.swift'], ['tool', 'Bash: swift build'], ['working', 'Fixing a type mismatch in Entry'], ['tool', 'Edit: Sources/Widget/Entry.swift']] },
    { project: 'landing-page', tool: 'Claude', state: 'idle', snippet: 'Bash: npm run build', t: now - 2 * m },
    { project: 'data-pipeline', tool: 'Claude', state: 'waiting', snippet: 'Allow Bash: rm -rf build/ ?', t: now - 6 * m },
    { project: 'docs-site', tool: 'Codex', state: 'idle', snippet: 'Done. Updated 4 files.', t: now - 48 * m },
  ];
  sessions.forEach(s => { s.step = 0; });
  function render() {
    const sorted = sessions.slice().sort((a, b) => b.t - a.t);
    $('#aList', el).innerHTML = sorted.map(s => {
      const [label, color] = STATE[s.state];
      return `<div class="arow"><span class="dot" style="background:${color}"></span>
        <div class="am"><div class="a1"><span class="ap ell">${esc(s.project)}</span><span class="atool">${s.tool}</span><span class="ast ell" style="color:${color}">${label}</span></div>
        <div class="asn ell">${esc(s.snippet || '—')}</div></div>
        <span class="aago">${ago(s.t)}</span></div>`;
    }).join('');
  }
  // Every 4 s, like the app's rescan, the two active sessions move on a step.
  setInterval(() => {
    sessions.forEach(s => {
      if (!s.script) return;
      s.step = (s.step + 1) % s.script.length;
      [s.state, s.snippet] = s.script[s.step];
      s.t = Date.now();
    });
    if (M.open && M.tab === 'agents') render();
  }, 4000);
  return { show: render };
})();
panes.agents = Agents;

// ---------- settings sheet (gear) ----------

const Settings = (() => {
  const el = document.createElement('div');
  el.className = 'settings'; el.hidden = true;
  el.innerHTML = `
    <div class="set-h">Settings ${sample('Demo')}<span class="grow"></span>${ib('x', 10, 'dim', 'Close settings', 'data-a="close"')}</div>
    <div class="set-row" role="switch" tabindex="0" data-k="hover" aria-checked="true"><span class="grow">Open on hover<small>Off: tap or click the notch instead</small></span><span class="switch on"></span></div>
    <div class="set-row" role="switch" tabindex="0" data-k="glow" aria-checked="false"><span class="grow">Glow<small>A slow rainbow edge around the notch</small></span><span class="switch"></span></div>
    <span class="set-note">The Mac app adds a glass theme, haptics and per-section switches.</span>`;
  content.appendChild(el);
  function flip(row) {
    const k = row.dataset.k;
    M[k] = !M[k];
    row.setAttribute('aria-checked', String(M[k]));
    $('.switch', row).classList.toggle('on', M[k]);
    if (k === 'glow') notch.classList.toggle('glowing', M.glow);
    $('#hintText').textContent = M.hover && !touchOnly ? 'Rest the pointer on the notch' : 'Tap the notch';
  }
  el.addEventListener('click', e => {
    if (e.target.closest('[data-a="close"]')) return close();
    const row = e.target.closest('.set-row');
    if (row) flip(row);
  });
  el.addEventListener('keydown', e => {
    const row = e.target.closest('.set-row');
    if (row && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); flip(row); }
  });
  function close() { el.hidden = true; $('#gearBtn')?.classList.add('dim'); }
  return {
    toggle() { el.hidden = !el.hidden; $('#gearBtn').classList.toggle('dim', el.hidden); },
    close,
  };
})();

// ---------- page ----------

setTab('home');
if (touchOnly) $('#hintText').textContent = 'Tap the notch';

// Things to try
$$('.chip').forEach(c => c.addEventListener('click', () => {
  switch (c.dataset.try) {
    case 'timer10': openPanel('timer'); Timer.begin(10, '10 sec'); break;
    case 'pomodoro': openPanel('timer'); Timer.pomodoro(); break;
    case 'prompter': openPanel('prompter'); Prompter.start(false); break;
    case 'shelf': openPanel('shelf'); if (touchOnly) $('#filePick').click(); else toastInPanel('Drag a file from your desktop onto the notch'); break;
    case 'clips': openPanel('clipboard'); break;
    case 'toast': closePanel(); toast('bell', 'Build finished', C.orange, 5); break;
    case 'playlists': openPanel('home'); Player.browse(); break;
    case 'mirror': openPanel('mirror'); break;
  }
}));

// Menu bar clock
const mbClock = $('#mbClock');
function tickClock() {
  const d = new Date();
  const time = d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  mbClock.textContent = window.innerWidth < 600 ? time : `${d.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' })}  ${time}`;
}
tickClock();
setInterval(tickClock, 10000);
addEventListener('resize', tickClock);

// Debug/automation handle, like topside-ctl.
window.topside = { open: openPanel, close: closePanel, toast, tab: setTab };
})();
