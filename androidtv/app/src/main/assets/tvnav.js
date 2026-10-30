(function(){
  if (window.__tvNav3) return 'already';
  window.__tvNav3 = true;

  // Two visibility tests on purpose.
  //  - onScreen(): what a viewer can currently see. Used for the guide and rail.
  //  - usable():   exists and is laid out, even if scrolled out of sight. Used inside an
  //                overlay, because filtering to on-screen only is why the card list could
  //                not be scrolled: every card below the fold was dropped from the list, so
  //                focus could never travel there to drag the panel down.
  function usable(el){
    if (!el || el.getClientRects().length === 0) return false;
    var cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.opacity === '0' || cs.display === 'none') return false;
    var r = el.getBoundingClientRect();
    return r.width >= 8 && r.height >= 8;
  }
  function onScreen(el){
    if (!usable(el)) return false;
    var r = el.getBoundingClientRect();
    return r.bottom > 2 && r.top < innerHeight - 2;
  }
  function collect(root, sel, test){
    return Array.prototype.slice.call(root.querySelectorAll(sel)).filter(test || onScreen);
  }
  function settingsRoot(){ return document.querySelector('.config-overlay.open'); }
  function pickerRoot(){ return document.querySelector('.server-picker.active'); }
  function guideShown(){
    var g = document.querySelector('.grid-body');
    if (!g) return false;
    var r = g.getBoundingClientRect();
    return r.height > 40 && r.top < innerHeight;
  }

  function fsMenuRoot(){
    var el = document.getElementById('fs-overlay');
    return (el && el.classList.contains('visible')) ? el : null;
  }
  function current(){
    var f = fsMenuRoot();
    if (f) return { name: 'fsmenu', list: collect(f, '.fs-ctl', usable) };
    var s = settingsRoot();
    if (s) return { name: 'settings',
      list: collect(s, 'button, .config-tab, [role=button], input, .bundle-row, .config-row', usable) };
    var p = pickerRoot();
    if (p) return { name: 'picker',
      list: collect(p, '.server-option, .server-picker-addr, .server-picker-connect, button', usable) };
    var rail = collect(document, '.v-btn');
    if (rail.length && rail.indexOf(document.activeElement) >= 0)
      return { name: 'rail', list: rail };
    var a = document.activeElement;
    if (a && a !== document.body && onScreen(a) &&
        (a.tagName === 'BUTTON' || a.tagName === 'INPUT' ||
         a.getAttribute('role') === 'button' || a.tabIndex >= 0) &&
        !a.closest('.grid-body'))
      return { name: 'native', list: [] };
    if (guideShown()) {
      // The announcement banner is part of the guide: its buttons sit directly above
      // channel 1 and were unreachable because the page's cursor only visits channels.
      return { name: 'guide',
        list: collect(document, '.grid-row[data-channel-id]', usable)
              .concat(collect(document, '.grid-row--promo button', usable)) };
    }
    return { name: 'player', list: [] };
  }

  function step(from, dir){
    var list = current().list;
    if (!list.length) return null;
    if (!from || list.indexOf(from) < 0) return list[0];
    var a = from.getBoundingClientRect();
    var ax = a.left + a.width / 2, ay = a.top + a.height / 2;
    var best = null, bestScore = Infinity;
    list.forEach(function(el){
      if (el === from) return;
      var b = el.getBoundingClientRect();
      var bx = b.left + b.width / 2, by = b.top + b.height / 2;
      var dx = bx - ax, dy = by - ay, along, across;
      if (dir === 'up')         { if (b.bottom > a.top + 4)    return; along = -dy; across = Math.abs(dx); }
      else if (dir === 'down')  { if (b.top < a.bottom - 4)    return; along =  dy; across = Math.abs(dx); }
      else if (dir === 'left')  { if (b.right > a.left + 4)    return; along = -dx; across = Math.abs(dy); }
      else                      { if (b.left < a.right - 4)    return; along =  dx; across = Math.abs(dy); }
      if (along <= 0) return;
      var score = along + across * 2;
      if (score < bestScore) { bestScore = score; best = el; }
    });
    return best;
  }

  function ring(el){
    if (!el) return false;
    try { el.focus(); } catch (e) {}
    try { el.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch (e) {}
    Array.prototype.forEach.call(document.querySelectorAll('.tv-focus'),
      function(o){ o.classList.remove('tv-focus'); });
    if (el.getAttribute && el.getAttribute('data-channel-id'))
      ringChannelId = el.getAttribute('data-channel-id');
    el.classList.add('tv-focus');
    return true;
  }
  window.__tvRing = ring;

  // Tuning and time-shifting both rebuild the guide, which throws away the ringed element.
  // Without this the amber ring vanished and the only highlight left was the page's own
  // cursor - which sat on row 1, so every selection looked ignored.
  var ringChannelId = null;
  function scheduleRingRefresh(delay){
    setTimeout(function () {
      var el = (ringChannelId &&
                document.querySelector('.grid-row[data-channel-id="' + ringChannelId + '"]')) ||
               document.querySelector('.grid-row.active') ||
               document.querySelector('.grid-row[data-channel-id]');
      if (el) ring(el);
    }, delay || 150);
  }
  window.__tvRingRefresh = scheduleRingRefresh;

  window.__tvClose = function(){
    var s = settingsRoot();
    if (s) { var c = s.querySelector('.config-close'); if (c) { c.click(); return 'closed:settings'; } }
    var p = pickerRoot();
    if (p) {
      var b = p.querySelector('.server-picker-back, .server-picker-close');
      if (b) { b.click(); return 'closed:picker'; }
      return 'closed:picker?';
    }
    return 'top';
  };

  window.__tvToGuide = function(){
    var r = document.querySelector('.grid-row.active') || document.querySelector('.grid-row[data-channel-id]');
    if (r) { ring(r); return 'guide'; }
    var rb = document.querySelector('.v-btn'); if (rb) rb.blur();
    return 'noguide';
  };

  // Exit lives on the rail, visibly, so leaving is a choice you can see rather than a
  // hidden button combination. It navigates to a scheme only the shell answers.
  function ensureExit(){
    var btns = document.querySelectorAll('.v-btn');
    if (!btns.length || document.querySelector('.bolextv-exit')) return;
    var last = btns[btns.length - 1];
    var b = document.createElement('button');
    b.className = last.className + ' bolextv-exit';
    b.innerHTML = last.innerHTML.replace(/([^>]*)<\/?[^>]*>?/, '$1');
    b.textContent = 'EXIT';
    b.setAttribute('aria-label', 'Exit BolexTV');
    b.style.marginTop = '10px';
    b.addEventListener('click', function(){ location.href = 'bolextv://exit'; });
    last.parentNode.appendChild(b);
  }
  setInterval(ensureExit, 1000);

  function sync(){
    var rail = document.querySelector('.v-btn.tv-focus');
    var t = 'BolexTV:' + (settingsRoot() || pickerRoot() ? 'ov'
            : fsMenuRoot() ? 'fsmenu'
            : document.fullscreenElement ? 'fs'
            : rail ? 'rail'
            : (guideShown() ? 'guide' : 'player'));
    if (document.title !== t) document.title = t;
  }
  window.__tvSync = function(){ sync(); return document.title; };

  // The guide is re-rendered on a timer and after every tune, which destroys the ringed node.
  // A one-shot refresh is not enough - it gets wiped by the next render - so the ring is
  // restored whenever it has gone missing while the guide is on screen and nothing else holds
  // focus. Without this the next Down starts from the top of the guide, which is exactly the
  // "my selection jumps back to the first channel" report.
  function ensureRing(){
    if (!guideShown()) return;
    // A ring left on a control that is no longer on screen is not a ring: it blocks the
    // restore below and makes OK look dead. Drop it and re-ring where the viewer actually is.
    var cur = document.querySelector('.tv-focus');
    if (cur && cur.getClientRects().length === 0) { cur.classList.remove('tv-focus'); cur = null; }
    if (cur) return;
    var el = (ringChannelId && document.querySelector('.grid-row[data-channel-id="' + ringChannelId + '"]')) ||
             document.querySelector('.grid-row.active');
    if (el) ring(el);
  }
  setInterval(function(){ sync(); ensureRing(); }, 500);
  sync();

  // The remote's OK arrives at a WebView as a CLICK on the focused element, not as a keydown,
  // so a keydown branch can never see it. Pressing OK on the channel that is already playing
  // means "fill the screen" - the row's own handler ignores it (tuneFromGuide returns early
  // for the current channel), so this is what makes a second OK do something.
  document.addEventListener('click', function (e) {
    var exitCtl = e.target && e.target.closest ? e.target.closest('.fs-ctl[data-fs="exit"]') : null;
    if (exitCtl) {
      // On the box, leaving full screen means bringing the guide back.
      if (window.__tvShowGuide) window.__tvShowGuide();
      if (window.__tvFsMenu) window.__tvFsMenu(false);
      return;
    }
    var row = e.target && e.target.closest ? e.target.closest('.grid-row') : null;
    if (!row || !row.classList.contains('active')) return;
    if (row.classList.contains('grid-row--promo')) return;
    if (window.__tvHideGuide) window.__tvHideGuide();
    else if (window.__tvToggleFullscreen) window.__tvToggleFullscreen();
  }, true);

  window.addEventListener('keydown', function(e){
    var k = e.key || '', kc = e.keyCode;
    var up = (k === 'ArrowUp'    || kc === 38 || kc === 19);
    var down = (k === 'ArrowDown'  || kc === 40 || kc === 20);
    var left = (k === 'ArrowLeft'  || kc === 37);
    var right = (k === 'ArrowRight' || kc === 39);
    var ok = (k === 'Enter' || kc === 13 || kc === 23 || kc === 66);
    var back = (k === 'Escape' || kc === 4);
    var z = current();
    if (z.name === 'native') return;

    if (z.name === 'fsmenu') {
      if (up || down || left || right) {
        var fm = step(document.activeElement, up ? 'up' : down ? 'down' : left ? 'left' : 'right');
        if (fm) ring(fm);
        e.preventDefault(); e.stopPropagation(); return;
      }
      if (ok) {
        var fa = document.activeElement;
        if (fa && z.list.indexOf(fa) >= 0 && fa.click) fa.click();
        e.preventDefault(); e.stopPropagation(); return;
      }
      if (back) { if (window.__tvFsMenu) window.__tvFsMenu(false); e.preventDefault(); e.stopPropagation(); return; }
      return;
    }

    if (z.name === 'settings' || z.name === 'picker') {
      if (up || down || left || right) {
        var t = step(document.activeElement, up ? 'up' : down ? 'down' : left ? 'left' : 'right');
        if (t) ring(t);
        e.preventDefault(); e.stopPropagation(); return;
      }
      if (ok) {
        var a = document.activeElement;
        if (a && z.list.indexOf(a) >= 0 && a.click) a.click();
        e.preventDefault(); e.stopPropagation(); return;
      }
      if (back) { window.__tvClose(); e.preventDefault(); e.stopPropagation(); return; }
      return;
    }

    if (z.name === 'rail') {
      if (up || down) {
        var i = z.list.indexOf(document.activeElement);
        var n = Math.min(Math.max(i + (down ? 1 : -1), 0), z.list.length - 1);
        ring(z.list[n]);
        e.preventDefault(); e.stopPropagation(); return;
      }
      if (ok) {
        if (document.activeElement && document.activeElement.click) document.activeElement.click();
        e.preventDefault(); e.stopPropagation(); return;
      }
      if (right || back) { window.__tvToGuide(); e.preventDefault(); e.stopPropagation(); return; }
      if (left) { e.preventDefault(); e.stopPropagation(); return; }
      return;
    }

    if (z.name === 'guide') {
      var inPromo = document.activeElement && document.activeElement.closest &&
                    document.activeElement.closest('.grid-row--promo');
      if (left) {
        // Rewind the guide window when it has been walked forward. At the live edge Left is
        // still the way into the rail, which is the route to the buttons Alex uses.
        var back = window.__tvTimeShift ? window.__tvTimeShift(-1) : 'edge';
        if (back === 'shifted') { scheduleRingRefresh(160); e.preventDefault(); e.stopPropagation(); return; }
        var rail = collect(document, '.v-btn');
        if (rail.length) { ring(rail[0]); e.preventDefault(); e.stopPropagation(); }
        return;
      }
      if (right) {
        // On the announcement the three buttons sit side by side; elsewhere right walks
        // the guide's time axis, which did nothing at all before it existed.
        if (inPromo) {
          var pn = step(document.activeElement, 'right');
          if (pn) ring(pn);
        } else if (window.__tvTimeShift) {
          window.__tvTimeShift(1);
          scheduleRingRefresh(180);
        }
        e.preventDefault(); e.stopPropagation();
        return;
      }
      if (up || down) {
        var origin = document.activeElement;
        if (!origin || z.list.indexOf(origin) < 0)
          origin = document.querySelector('.grid-row.active') || document.querySelector('.grid-row.focused');
        var g = step(origin, up ? 'up' : 'down');
        if (g) ring(g);
        // Consume even when there is nowhere to go: falling through drops focus to the body
        // and the ring disappears, which reads as a dead remote.
        e.preventDefault(); e.stopPropagation();
        return;
      }
      if (ok) {
        var el = document.activeElement;
        if (!el || z.list.indexOf(el) < 0) el = document.querySelector('.grid-row.active');
        if (el && el.classList && el.classList.contains('active')) {
          // Already watching this channel: a second OK means "fill the screen", which is what a
          // TV guide does. tuneFromGuide() returns early on the current channel, so before this
          // the press did nothing at all.
          if (window.__tvToggleFullscreen) window.__tvToggleFullscreen();
          e.preventDefault(); e.stopPropagation();
          return;
        }
        if (el && el.click) {
          el.click();
          scheduleRingRefresh(900);
          e.preventDefault(); e.stopPropagation();
        }
        return;
      }
      return;
    }
  }, true);

  return 'armed';
})();
