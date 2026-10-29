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
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
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
        return super.onKeyDown(keyCode, event)
    }

    private fun changeChannel(delta: Int) {
        evaluate(
            """
            (function(){
              try{
                var ev = new CustomEvent('bolextv:channel', {detail:{delta:$delta}});
                window.dispatchEvent(ev);
                var key = $delta > 0 ? 'ChannelUp' : 'ChannelDown';
                var kc  = $delta > 0 ? 166 : 167;
                window.dispatchEvent(new KeyboardEvent('keydown',
                  {key:key, code:key, keyCode:kc, which:kc, bubbles:true, cancelable:true}));
                return 'channel:'+$delta;
              }catch(e){ return 'error:'+e.message; }
            })();
            """.trimIndent()
        )
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

    private companion object {
        const val TAG = "BolexTV"
    }
}
