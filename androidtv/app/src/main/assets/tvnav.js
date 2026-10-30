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

  function current(){
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
    // The page highlights its own guide cursor; with the shell painting the ring, two
    // highlights on screen at once is a lie about where the remote is pointing.
    Array.prototype.forEach.call(document.querySelectorAll('.grid-row.focused'),
      function(o){ if (o !== el) o.classList.remove('focused'); });
    el.classList.add('tv-focus');
    return true;
  }
  window.__tvRing = ring;

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
            : rail ? 'rail'
            : (guideShown() ? 'guide' : 'player'));
    if (document.title !== t) document.title = t;
  }
  window.__tvSync = function(){ sync(); return document.title; };
  setInterval(sync, 500);
  sync();

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
      // Left still opens the rail; everything else walks the guide, announcement first.
      if (left) {
        var rail = collect(document, '.v-btn');
        if (rail.length) { ring(rail[0]); e.preventDefault(); e.stopPropagation(); }
        return;
      }
      if (up || down || right) {
        // Right matters on the announcement: its three buttons sit side by side and
        // nothing else in the guide is reachable to the right.
        var g = step(document.activeElement, up ? 'up' : down ? 'down' : 'right');
        if (g) ring(g);
        // Consume the key even when there is nowhere to go: letting it fall through
        // drops focus to the body and the ring disappears, which reads as a dead remote.
        e.preventDefault(); e.stopPropagation();
        return;
      }
      if (ok) {
        var el = document.activeElement;
        if (!el || z.list.indexOf(el) < 0) el = document.querySelector('.grid-row.active');
        if (el && el.click) { el.click(); e.preventDefault(); e.stopPropagation(); }
        return;
      }
      return;
    }
  }, true);

  return 'armed';
})();
