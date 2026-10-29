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
            view.evaluateJavascript(NAV_JS, null)
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
                    goToGuide()
                    return true // never exit: back means "up one level", not "quit"
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
        // The tuner's player mode already binds ArrowUp -> prevChannel() and ArrowDown ->
        // nextChannel() (plex-tuner.html:9793-9802), so dispatching those keys needs no upstream
        // change at all. CH+ means "up one channel", i.e. ArrowUp. The CustomEvent is dispatched
        // as well so a future Phase 2 bridge has a stable contract to attach to.
        evaluate(
            """
            (function(){
              try{
                window.dispatchEvent(new CustomEvent('bolextv:channel', {detail:{delta:$delta}}));
                var key = $delta > 0 ? 'ArrowUp' : 'ArrowDown';
                var kc  = $delta > 0 ? 38 : 40;
                var t   = document.activeElement || document.body;
                var ev  = new KeyboardEvent('keydown',
                  {key:key, code:key, keyCode:kc, which:kc, bubbles:true, cancelable:true});
                t.dispatchEvent(ev);
                if (t !== document.body) document.dispatchEvent(ev);
                return 'channel:'+$delta;
              }catch(e){ return 'error:'+e.message; }
            })();
            """.trimIndent()
        ) { result -> android.util.Log.d(TAG, "channel -> $result") }
    }

    /** Back button: ask the page to return to the guide, whatever it currently shows. */
    private fun goToGuide() {
        evaluate(
            """
            (function(){
              try{
                if (window.BolexTV && typeof BolexTV.showGuide === 'function')
                  { BolexTV.showGuide(); return 'bridge:showGuide'; }
                var g = document.querySelector('[data-bolextv-guide]');
                if (g && g.click) { g.click(); return 'click:guide'; }
                var b = document.querySelector('[data-bolextv-back]');
                if (b && b.click) { b.click(); return 'click:back'; }
                window.dispatchEvent(new KeyboardEvent('keydown',
                  {key:'Escape', code:'Escape', keyCode:27, which:27, bubbles:true}));
                return 'escape';
              }catch(e){ return 'error:'+e.message; }
            })();
            """.trimIndent()
        ) { result ->
            // Deliberately no finish() on any branch: nothing here can strand the app.
            android.util.Log.d(TAG, "guide -> $result")
        }
    }

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
            "  return t + ' ||FOCUS:' + f + ' ||NAV:' + (window.__bolextvNav ? 'armed' : 'none');" +
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
              if (document.getElementById('bolextv-brand')) return 'already';
              var old = document.querySelector('img[alt="NOSTALGEX"]')
                     || document.querySelector('img[src*="nostalgex"]');
              if (!old) return 'no-logo';
              var box = document.createElement('span');
              box.id = 'bolextv-brand';
              box.style.cssText = 'display:inline-flex;align-items:center;gap:18px;';
              var img = document.createElement('img');
              img.alt = 'BolexTV';
              img.src = 'data:image/svg+xml;base64,$b64';
              img.style.cssText = 'height:84px;width:84px;display:block;';
              var word = document.createElement('span');
              word.textContent = 'BOLEXTV';
              word.style.cssText = "font-family:'Press Start 2P','VT323',monospace;" +
                                   "font-size:30px;letter-spacing:6px;color:#F2EAE1;";
              box.appendChild(img);
              box.appendChild(word);
              old.replaceWith(box);
              document.title = 'BolexTV';
              return 'rebranded';
            })();
        """.trimIndent()
    }

    private companion object {
        const val TAG = "BolexTV"

        /** Guide Play, verbatim from brand/assets/bolextv-logo-guide-play-20261029-v1.svg. */
        const val BRAND_SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img"><rect x="112" y="112" width="800" height="800" rx="224" fill="#E9A13B"/><path d="M232 358 L232 666 L470 512 Z" fill="#12151A"/><rect x="506" y="358" width="280" height="76" rx="18" fill="#12151A"/><rect x="506" y="474" width="280" height="76" rx="18" fill="#12151A"/><rect x="506" y="590" width="188" height="76" rx="18" fill="#12151A"/></svg>"""

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
        val NAV_JS = """
            (function(){
              if (window.__bolextvNav) return 'already';
              window.__bolextvNav = true;
              function items(){
                var p = document.querySelector('.server-picker.active');
                if (!p) return [];
                // Filter to what is actually rendered. The tuner hides SHOW ADDRESSES on
                // non-touch devices (:7865), and focusing a display:none element silently
                // does nothing - which stranded the cursor one step short of CONNECT.
                return Array.prototype.slice.call(
                  p.querySelectorAll('.server-option, .server-picker-addr, .server-picker-connect'))
                  .filter(function(el){ return el.getClientRects().length > 0; });
              }
              document.addEventListener('keydown', function(e){
                var list = items();
                if (!list.length) return;                 // picker closed: leave the page alone
                var kc = e.keyCode;
                var k = e.key || '';
                var down = (k === 'ArrowDown' || kc === 40 || kc === 20);
                var up = (k === 'ArrowUp' || kc === 38 || kc === 19);
                var act = (k === 'Enter' || kc === 13 || kc === 23 || kc === 66
                           || k === 'ArrowLeft' || k === 'ArrowRight' || kc === 37 || kc === 39);
                if (!down && !up && !act) return;
                var cur = list.indexOf(document.activeElement);
                if (down || up) {
                  var nxt = cur < 0 ? 0 : (down ? Math.min(cur + 1, list.length - 1)
                                                : Math.max(cur - 1, 0));
                  list[nxt].focus();
                  list[nxt].scrollIntoView({block:'nearest'});
                } else if (cur >= 0) {
                  var keep = cur;
                  list[cur].click();
                  // A row click re-renders the list, so restore the cursor where it was.
                  var after = items();
                  if (after[keep] && after[keep] !== list[cur]) {
                    after[keep].focus();
                    after[keep].scrollIntoView({block:'nearest'});
                  }
                }
                e.preventDefault();
                e.stopPropagation();
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
