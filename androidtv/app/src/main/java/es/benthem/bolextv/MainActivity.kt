package es.benthem.bolextv

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.TextView

/**
 * BolexTV — a kiosk shell around the self-hosted Nostalgex tuner.
 *
 * Phase 1 scope (docs/PLAN-20261029-v1.md): launcher tile, kiosk WebView pinned to the tuner,
 * remote key handling, back returns to the guide and never exits.
 *
 * There is deliberately no JavaScript bridge yet. The tuner exposes none (verified: zero
 * occurrences of postMessage / addJavascriptInterface / window.BolexTV in plex-tuner.html), so
 * adding one is the Phase 2 ADR. Until then this class speaks to the page only through
 * dispatched DOM events, which cannot silently corrupt page state.
 */
class MainActivity : Activity() {

    private lateinit var root: FrameLayout
    private lateinit var webView: WebView
    private var customView: View? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // A TV client is never backgrounded on purpose; let the panel sleep on its own schedule.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        hideSystemUi()

        root = FrameLayout(this)
        root.setBackgroundColor(Color.BLACK)

        webView = buildWebView()
        root.addView(
            webView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        setContentView(root)
        webView.loadUrl(BuildConfig.TUNER_URL)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun buildWebView(): WebView = WebView(this).apply {
        setBackgroundColor(Color.BLACK)
        isFocusable = true
        isFocusableInTouchMode = true

        settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true

            // Measured on the Mi Box (docs/FIELD-RESULTS-20261029-v1.md): a media URL renders a
            // single frame and never starts audio unless a user gesture is allowed. The tuner's
            // own channel tap satisfies Chrome's rule, but a kiosk shell must not depend on that
            // for every entry point, so autoplay is permitted outright.
            mediaPlaybackRequiresUserGesture = false

            // Ten-foot UI: no pinch, no double-tap zoom, no zoom controls.
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
            loadWithOverviewMode = true
            useWideViewPort = true
            cacheMode = WebSettings.LOAD_DEFAULT
        }

        CookieManager.getInstance().setAcceptCookie(true)
        webViewClient = KioskClient()
        webChromeClient = KioskChromeClient()
        requestFocus()
    }

    /** Keep every navigation inside the app; a kiosk must never strand the user in a dead view. */
    private inner class KioskClient : WebViewClient() {
        override fun shouldOverrideUrlLoading(
            view: WebView,
            request: WebResourceRequest
        ): Boolean = false // stay inside; the tuner is the whole world here

        override fun onPageFinished(view: WebView, url: String) {
            // Kiosk CSS. The tuner is laid out for a browser window; on a 1080p TV the server
            // picker grows past the viewport and its CONNECT button lands below the fold with no
            // scrollable ancestor (plex-tuner.html:1170-1180 sets neither max-height nor overflow),
            // so neither D-pad nor touch can reach it. Bound the picker, let it scroll, and pin the
            // connect button to the bottom of that scroll box so it is always visible.
            view.evaluateJavascript(TV_CSS, null)
            view.evaluateJavascript(brandScript(), null)
            view.evaluateJavascript(TVNAV_JS, null)
            view.evaluateJavascript(TIME_JS, null)
        }

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError
        ) {
            if (!request.isForMainFrame) return
            // Never leave a black screen with no explanation: say what failed and where.
            val html = """
                <html><body style="background:#12151A;color:#F2EAE1;font-family:sans-serif;
                display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
                <div style="text-align:center">
                  <div style="font-size:28px;color:#E9A13B;margin-bottom:12px">
                    Cannot reach the tuner
                  </div>
                  <div style="font-size:18px;opacity:.8">${BuildConfig.TUNER_URL}</div>
                  <div style="font-size:16px;opacity:.6;margin-top:10px">${error.description}</div>
                </div></body></html>
            """.trimIndent()
            view.loadDataWithBaseURL(null, html, "text/html", "utf-8", null)
        }
    }

    /** Fullscreen HTML5 video (the tuner plays into a video element). */
    private inner class KioskChromeClient : WebChromeClient() {
        override fun onShowCustomView(view: View, callback: CustomViewCallback) {
            if (customView != null) {
                callback.onCustomViewHidden()
                return
            }
            customView = view
            root.addView(
                view,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            )
            webView.visibility = View.GONE
        }

        override fun onHideCustomView() {
            customView?.let { root.removeView(it) }
            customView = null
            webView.visibility = View.VISIBLE
            webView.requestFocus()
        }
    }

    /**
     * Remote handling.
     *
     * CH+ / CH- are intercepted because a WebView ignores those key codes entirely — without this
     * they do nothing at all. D-pad is left alone on purpose: the WebView already maps it to focus
     * movement, and the guide grid needs up/down to move within the grid. Making D-pad mean
     * "channel" while watching is genuinely mode-dependent, so it belongs to the Phase 2 bridge
     * contract rather than being guessed at here.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (event.action == KeyEvent.ACTION_DOWN) {
            // Debug builds: dump what the page actually rendered on every key, so a blank-looking
            // screen can be distinguished from a screen whose text merely failed to paint.
            if (BuildConfig.DEBUG) dumpPageText()
            when (keyCode) {
                KeyEvent.KEYCODE_CHANNEL_UP, KeyEvent.KEYCODE_CHANNEL_DOWN -> {
                    changeChannel(if (keyCode == KeyEvent.KEYCODE_CHANNEL_UP) +1 else -1)
                    return true
                }
                KeyEvent.KEYCODE_BACK -> {
                    onBackPressedTv()
                    return true
                }
                KeyEvent.KEYCODE_MENU -> {
                    toggleGuide()
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun changeChannel(delta: Int) {
        // Channel changing is done entirely in the page, because every key-based route measured
        // worse: a lone arrow moved the guide cursor and left the programme alone, and
        // arrow-then-click worked exactly once - after the click the DOM focus moves to the row,
        // so subsequent arrows stopped driving the guide and the cursor froze.
        //
        // The one route proven to tune is the guide row's own click: clicking
        // `.grid-row.focused` moved playback from "CH 20 FAMILY HOUR" to "CH 21 DIZ FLICKS".
        // So this reads which row is playing, steps to the next/previous row, and clicks it -
        // the same action a viewer performs with the pointer, and independent of key focus.
        //
        // evaluateJavascript does run during playback (this click is what tuned the channel);
        // its callback may not come back, so the log is diagnostic only.
        evaluate(
            """
            (function(){
              try{
                var rows = Array.prototype.slice.call(
                  document.querySelectorAll('.grid-row[data-channel-id]'));
                if (!rows.length) return 'no-rows';
                var at = rows.findIndex(function(r){ return r.classList.contains('active'); });
                if (at < 0) at = rows.findIndex(function(r){ return r.classList.contains('focused'); });
                if (at < 0) at = 0;
                var next = (at + ($delta) + rows.length) % rows.length;
                rows[next].click();
                return 'tuned:' + rows[next].getAttribute('data-channel-id') +
                       ' (' + (at + 1) + '/' + rows.length + ' -> ' + (next + 1) + ')';
              }catch(e){ return 'err:' + e.message; }
            })();
            """.trimIndent()
        ) { result -> android.util.Log.d(TAG, "channel delta=$delta -> $result") }
    }

    /**
     * Back has to mean one thing at a time, or it means nothing.
     *
     * Plex's model, which is what Alex asked for: Back closes whatever is on top, and only at the
     * very top does it offer to leave. The layer is read from the page title because that is the
     * one value readable synchronously - the JS callback can go silent exactly when Back is
     * pressed, and a Back that sometimes does nothing is worse than no Back at all.
     */
    private fun onBackPressedTv() {
        val layer = webView.title ?: ""
        when {
            layer.contains(":ov") -> {
                // Settings or server picker is open: let the page close it.
                evaluate("window.__tvClose ? window.__tvClose() : 'none'") { r ->
                    android.util.Log.d(TAG, "back closed overlay -> $r")
                }
            }
            layer.contains(":player") -> {
                // Watching something: Back reveals the guide, it does not leave.
                evaluate(
                    "(function(){var r=document.querySelector('.grid-row.focused')||document.querySelector('.grid-row.active');" +
                    "if(r){r.focus();}var g=document.querySelector('.grid-body');" +
                    "if(g){g.scrollIntoView({block:'nearest'});}return 'guide';})()"
                ) { r -> android.util.Log.d(TAG, "back -> guide $r") }
            }
            else -> confirmExit()
        }
    }

    /** Ask before leaving. A kiosk that a mis-press can close is a support call. */
    private fun confirmExit() {
        if (isFinishing) return
        val dialog = android.app.AlertDialog.Builder(this)
            .setTitle("Leave BolexTV?")
            .setMessage("You will return to the Android TV home screen.")
            .setPositiveButton("Leave") { _, _ -> finishAndRemoveTask() }
            .setNegativeButton("Stay") { d, _ -> d.dismiss() }
            .setCancelable(true)
            .create()
        // Android focuses the positive button first, so a second OK would quit the app.
        // Leaving has to be the deliberate choice, not the accidental one.
        dialog.setOnShowListener {
            dialog.getButton(android.app.AlertDialog.BUTTON_NEGATIVE)?.requestFocus()
        }
        dialog.show()
    }

    /** MENU key: the page toggles its own guide on "m". */
    private fun toggleGuide() = evaluate(
        "(function(){try{window.dispatchEvent(new KeyboardEvent('keydown'," +
            "{key:'m',code:'KeyM',keyCode:77,which:77,bubbles:true}));return 'menu';}" +
            "catch(e){return 'error:'+e.message;}})();"
    ) { result -> android.util.Log.d(TAG, "menu -> $result") }

    private fun evaluate(script: String, onResult: ((String?) -> Unit)? = null) {
        webView.evaluateJavascript(script) { value ->
            // Never log page content or URLs with credentials; only the shim's own return value.
            onResult?.invoke(value)
        }
    }

    private fun hideSystemUi() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUi()
    }

    override fun onResume() {
        super.onResume()
        webView.onResume()
        webView.resumeTimers()
    }

    override fun onPause() {
        webView.onPause()
        webView.pauseTimers()
        super.onPause()
    }

    override fun onDestroy() {
        (webView.parent as? ViewGroup)?.removeView(webView)
        webView.destroy()
        super.onDestroy()
    }

    /** Debug-only: log the rendered page text so a blank screen can be told from an unpainted one. */
    private fun dumpPageText() {
        evaluate(
            "(function(){" +
            "  var a = document.activeElement;" +
            "  var f = a ? (a.className || a.tagName) : 'none';" +
            "  var t = (document.body && document.body.innerText || '').replace(/\\s+/g,' ').trim().slice(0,200);" +
            // The guide prints "CHANNEL n OF m", but the player does not, so the channel number
            // disappears exactly when a channel change is what is being measured. The player's
            // now-playing tag carries "CH nn - name" (plex-tuner.html:5062); surface it so the
            // Phase 1 channel measurements have a stable observable in both states.
            "  var tg = document.getElementById('np-channel-tag');" +
            "  var ch = tg ? (tg.textContent || '').replace(/\\s+/g,' ').trim() : '';" +
            "  return t + ' ||CH:' + ch + ' ||FOCUS:' + f + ' ||NAV:' + (window.__bolextvNav ? 'armed' : 'none');" +
            "})()"
        ) { text -> android.util.Log.d(TAG, "PAGE: $text") }
    }

    /**
     * Replaces the tuner's own wordmark with the BolexTV lockup.
     *
     * The app is BolexTV; the page it loads still announces NOSTALGEX, because the mark lives in
     * the tuner bundle (`plex-tuner.html:3406`, `img[alt="NOSTALGEX"]`). The mark is inlined here
     * as an SVG data URI rather than fetched, so the branding ships inside the APK and a tuner
     * update cannot revert it. Single source of truth for the geometry:
     * `brand/assets/bolextv-logo-guide-play-20261029-v1.svg`.
     */
    private fun brandScript(): String {
        val b64 = android.util.Base64.encodeToString(
            BRAND_SVG.toByteArray(Charsets.UTF_8),
            android.util.Base64.NO_WRAP
        )
        return """
            (function(){
              if (document.getElementById('bolextv-brand-done')) return 'already';
              var olds = Array.prototype.slice.call(document.querySelectorAll(
                'img[alt="NOSTALGEX"], img[alt="Nostalgex"], img[src*="nostalgex"]'));
              if (!olds.length) return 'no-logo';
              olds.forEach(function(o){
                // The page places this logo in five slots of very different sizes. The top bar is
                // 48px tall and its slot is 96px wide, so a full-size lockup spilled over the
                // now-playing artwork and was unreadable. Compact there, full lockup elsewhere.
                var compact = !!(o.closest && o.closest('.m-topbar'));
                var wrap = document.createElement('span');
                wrap.className = 'bolextv-brand';
                wrap.style.cssText = 'display:inline-flex;align-items:center;gap:10px;' +
                                     'max-width:100%;overflow:hidden;';
                var im = document.createElement('img');
                im.alt = 'BolexTV';
                im.src = 'data:image/svg+xml;base64,$b64';
                var wd = document.createElement('span');
                wd.textContent = 'BOLEXTV';
                if (compact) {
                  im.style.cssText = 'height:22px;width:22px;display:block;';
                  wd.style.cssText = "font-family:'VT323',monospace;font-size:17px;" +
                                     "letter-spacing:2px;color:#F2EAE1;line-height:1;";
                } else {
                  im.style.cssText = 'height:84px;width:84px;display:block;';
                  wd.style.cssText = "font-family:'Press Start 2P','VT323',monospace;font-size:30px;" +
                                     "letter-spacing:6px;color:#F2EAE1;";
                }
                wrap.appendChild(im);
                wrap.appendChild(wd);
                o.replaceWith(wrap);
              });
              var marker = document.createElement('span');
              marker.id = 'bolextv-brand-done';
              marker.style.display = 'none';
              document.body.appendChild(marker);
              document.title = 'BolexTV';
              return 'rebranded:' + olds.length;
            })();
        """.trimIndent()
    }

    private companion object {
        const val TAG = "BolexTV"

        /** Guide Play, verbatim from brand/assets/bolextv-logo-guide-play-20261029-v1.svg. */
        const val BRAND_SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img"><rect x="112" y="112" width="800" height="800" rx="224" fill="#E9A13B"/><path d="M232 358 L232 666 L470 512 Z" fill="#12151A"/><rect x="506" y="358" width="280" height="76" rx="18" fill="#12151A"/><rect x="506" y="474" width="280" height="76" rx="18" fill="#12151A"/><rect x="506" y="590" width="188" height="76" rx="18" fill="#12151A"/></svg>"""

        /**
         * 24-hour guide headers.
         *
         * The page renders EPG slots as "12:30 PM" (:4761-4765). The fork patch converts that to
         * 24-hour, but the page ships inside the tuner container, so the change only reaches the TV
         * once a new image is deployed. This does it at runtime so the TV is correct today; once the
         * image is rebuilt the patch takes over and this becomes a no-op (it only rewrites strings
         * that still carry AM/PM).
         */
        val TIME_JS = """
            (function(){
              function fix(){
                var slots = document.querySelectorAll('.grid-time-slot');
                for (var i = 0; i < slots.length; i++) {
                  var el = slots[i];
                  var m = /^(\d{1,2}):(\d{2})\s*(AM|PM)$/i.exec((el.textContent || '').trim());
                  if (!m) continue;
                  var h = parseInt(m[1], 10) % 12;
                  if (/pm/i.test(m[3])) h += 12;
                  el.textContent = (h < 10 ? '0' : '') + h + ':' + m[2];
                }
              }
              fix();
              try {
                new MutationObserver(fix).observe(document.body, {childList:true, subtree:true});
              } catch (e) {}
              return 'time24';
            })();
        """.trimIndent()

        /**
         * Remote navigation for the server picker.
         *
         * The tuner's own picker branch (plex-tuner.html:9746-9765) moves `serverFocusIndex` and
         * calls `renderServerOptions()`, but that renderer never applies the `.focused` class
         * (:7838 sets only `selected`), so the cursor is invisible. It also calls preventDefault(),
         * which blocks the browser's own focus movement, and rebuilding the list destroys whatever
         * node had focus. Result on a TV: up/down appear dead while the native ring stays pinned
         * to the first row.
         *
         * This listener runs in the CAPTURE phase, so it executes before the page's own document
         * handler and can stop it. It drives real DOM focus through the rows and the two buttons,
         * scrolls the focused row into view, and clicks on Enter. It only acts while the picker is
         * open, so player-mode arrow keys (channel change) are untouched.
         */
        val TVNAV_JS = """
            (function(){
              if (window.__tvNav2) return 'already';
              window.__tvNav2 = true;

              function visible(el){
                if (!el || el.getClientRects().length === 0) return false;
                var cs = getComputedStyle(el);
                if (cs.visibility === 'hidden' || cs.opacity === '0' || cs.display === 'none') return false;
                var r = el.getBoundingClientRect();
                if (r.width < 8 || r.height < 8) return false;
                // Anything parked off the top or bottom is not reachable: focusing it makes the
                // ring vanish and the remote appear dead. This is the settings-tabs bug.
                return r.bottom > 2 && r.top < innerHeight - 2;
              }
              function collect(root, sel){
                return Array.prototype.slice.call(root.querySelectorAll(sel)).filter(visible);
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
                  list: collect(s, 'button, .config-tab, [role=button], input, .bundle-card, .config-row') };
                var p = pickerRoot();
                if (p) return { name: 'picker',
                  list: collect(p, '.server-option, .server-picker-addr, .server-picker-connect, button') };
                var rail = collect(document, '.v-btn');
                if (rail.length && rail.indexOf(document.activeElement) >= 0)
                  return { name: 'rail', list: rail };
                // Any other real, focusable control means a popup we do not model (the quality
                // and sleep submenus). Those navigate natively, so hands off: hijacking them
                // made OK tune a channel while the user was picking a stream quality.
                var a = document.activeElement;
                if (a && a !== document.body && visible(a) &&
                    (a.tagName === 'BUTTON' || a.tagName === 'INPUT' ||
                     a.getAttribute('role') === 'button' || a.tabIndex >= 0) &&
                    !a.closest('.grid-body'))
                  return { name: 'native', list: [] };
                return { name: guideShown() ? 'guide' : 'player', list: [] };
              }

              // Geometric, not list order: works on every overlay the page may add later,
              // including rows whose DOM order does not match where they sit on screen.
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
                el.classList.add('tv-focus');
                return true;
              }
              window.__tvRing = ring;

              // Close whatever sits on top of the guide. Back is handled by the shell, which
              // asks this first so Back never means "quit" while something is open.
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

              // The shell reads the layer off the title, because that is the one value it can
              // read synchronously: a JS callback can go silent exactly when Back is pressed.
              function sync(){
                var t = 'BolexTV:' + (settingsRoot() || pickerRoot() ? 'ov'
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
                if (z.name === 'native') return;   // the page's own popup: do not interfere

                // Overlays the page does not drive itself: settings, server picker.
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

                // Side rail: walk it, activate, and let Right come back out.
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
                  if (right || back) { if (document.activeElement) document.activeElement.blur(); e.preventDefault(); e.stopPropagation(); return; }
                  if (left)  { e.preventDefault(); e.stopPropagation(); return; }
                  return;
                }

                // Guide and player: the page owns the arrows (its own cursor is the highlight),
                // so they are left untouched. OK is ours, because the page's Enter handler is
                // never reached from a remote - clicking the row is the route that tunes.
                if (left) {
                  var rail = collect(document, '.v-btn');
                  if (rail.length) { ring(rail[0]); e.preventDefault(); e.stopPropagation(); }
                  return;
                }
                if (ok && z.name === 'guide') {
                  var row = document.querySelector('.grid-row.focused') || document.querySelector('.grid-row.active');
                  if (row && row.click) { row.click(); e.preventDefault(); e.stopPropagation(); }
                  return;
                }
              }, true);

              return 'armed';
            })();
        """.trimIndent()

        /**
         * Kiosk-only CSS. Kept as a string so it ships with the APK and cannot be lost by a
         * tuner update; none of it changes what the tuner does, only whether its controls fit
         * on a television.
         */
        val TV_CSS = """
            (function(){
              if (document.getElementById('bolextv-tv-css')) return 'already';

              // --- 10-foot sizing. Measured on the box: the page renders at 960x540 CSS with a
              // device pixel ratio of 2, so a 42px title is 84px tall on the glass and wraps to
              // four lines on a long film name, while 16px guide rows are unreadable from a sofa
              // and the 160px channel column truncates "FAMILY HOUR" to "FAMILY H...".
              // Measured: .info-channel-tag occupies y 32..68 and .info-title started at y 66, so the
              // two overlapped by 2px - the "text on top of text" Alex photographed. A second line
              // then ran into the 2024 / es-12 / runtime badges at y 137.
              var sizing = ''
                + '.info-channel-tag{margin-bottom:6px !important;}'
                + '.info-title{font-size:26px !important;line-height:1.18 !important;margin-top:0 !important;'
                +   'display:-webkit-box !important;-webkit-line-clamp:2 !important;'
                +   '-webkit-box-orient:vertical;overflow:hidden;}'
                + '.grid-row{min-height:44px !important;}'
                + '.grid-row-channel{width:230px !important;min-width:230px !important;'
                +   'font-size:16px !important;line-height:1.2 !important;}'
                + '.grid-row-programs{font-size:17px !important;}'
                + '.grid-body{font-size:17px !important;}'
                // A focus ring the page does not draw itself: without it the remote looks dead,
                // because the page's own highlight only tracks its internal guide cursor.
                + '.tv-focus{outline:3px solid #E9A13B !important;outline-offset:2px !important;'
                +   'border-radius:8px !important;box-shadow:0 0 0 6px rgba(233,161,59,.22) !important;}'
                + '.v-btn.tv-focus,.config-close.tv-focus,.config-tab.tv-focus{background:rgba(233,161,59,.18) !important;}';
              var st = document.getElementById('bolextv-tv-css');
              if (!st) { st = document.createElement('style'); st.id = 'bolextv-tv-css';
                         document.head.appendChild(st); }
              st.textContent = sizing;
              var s = document.createElement('style');
              s.id = 'bolextv-tv-css';
              s.textContent = [
                'html,body{overflow-y:auto !important;}',
                '.server-picker.active{max-height:90vh !important;overflow:hidden !important;' +
                  'padding:4px 4px 8px !important;}',
                '.server-picker-list{flex:1 1 auto !important;min-height:0 !important;' +
                  'overflow-y:auto !important;overscroll-behavior:contain;}',
                // Not sticky: pinned, it sat on top of the last server row and looked unselectable.
                // As a normal flex child below the scroll area it can never cover a row.
                '.server-picker-connect{position:static !important;}'
              ].join('');
              document.head.appendChild(s);
              return 'injected';
            })();
        """.trimIndent()
    }
}
