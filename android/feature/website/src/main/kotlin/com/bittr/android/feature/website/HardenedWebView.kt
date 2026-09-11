package com.bittr.android.feature.website

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.net.http.SslError
import android.view.ViewGroup
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import com.bittr.android.core.lnurl.LnurlRequestSlot

/**
 * The **only** place in the app a [WebView] is constructed or configured.
 *
 * `WebViewHardeningGuardTest` in `:app` fails the build on any other file that
 * names `android.webkit.WebView` or `WebSettings`. That is what makes the R-11
 * baseline below a property of the app rather than of this screen: a second
 * WebView added later cannot come with its own, more relaxed settings — it either
 * calls this function or the tests go red.
 *
 * `JavascriptInterfaceGuardTest` covers the other half (R-1):
 * `addJavascriptInterface` appears nowhere in `android/`, enforced by that test
 * and by a CI grep, so the naive translation of iOS's `WKScriptMessageHandler`
 * cannot be added quietly. No bridge of any kind is attached here — see
 * [FirstPartyOrigins] for why, and note that `androidx.webkit` is not a
 * dependency of this module, so `addWebMessageListener` is not even on the
 * classpath.
 */
internal object HardenedWebView {

    /**
     * Whether JavaScript runs in the in-app browser.
     *
     * **This deviates from R-11's baseline, which says "off if no bridge ships",
     * and it is flagged on BIT-33 rather than left for a reviewer to find.**
     *
     * The reasoning: with no bridge attached and Lightning navigations dropped,
     * JavaScript in the page has no wallet capability at all. What it has is the
     * Chrome renderer sandbox, the same one it gets in the system browser, with
     * Safe Browsing on, mixed content refused, SSL errors fatal and every file
     * and universal-access setting off. Turning JavaScript off does not narrow the
     * path to the wallet — the missing bridge already closed it — it just stops
     * the pages rendering: `mempool.space` is a JavaScript application and the
     * BTCMap merchant sites largely are too, so they would come up blank. The
     * user's escape from a blank page is the open-externally button, which hands
     * the same URL to the system browser with JavaScript on. So the setting costs
     * two of the three call sites their content and buys no reduction in exposure.
     *
     * One constant, one call site: if the Application Security Engineer disagrees,
     * this is a one-word change and every other control stays as it is.
     */
    private const val JAVASCRIPT_ENABLED = true

    /**
     * Builds a hardened [WebView].
     *
     * @param onProgress fires for every progress change, 0–100. Drives the
     *   [LinearProgressIndicator] that replaces iOS's indeterminate spinner
     *   (DEV-57).
     * @param onPageUrlChanged fires when the committed URL changes, so the caller
     *   can re-derive trust. **Load-bearing:** a page that redirects off
     *   `getbittr.com`, or a link followed three hops out, must be reclassified
     *   rather than keeping the trust of whatever opened the screen.
     * @param lnurlSlot cancelled on every navigation (R-10). In v1 nothing can
     *   claim it from a web page — no bridge — so this is the empty half of the
     *   requirement, wired up because the cancellation site is the part that is
     *   easy to forget when the bridge lands, not the claim site.
     */
    @SuppressLint("SetJavaScriptEnabled")
    fun create(
        context: Context,
        onProgress: (Int) -> Unit,
        onPageUrlChanged: (String?) -> Unit,
        lnurlSlot: LnurlRequestSlot,
    ): WebView = WebView(context).apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )

        // R-11 hardening baseline. Every line is a deliberate default, so they are
        // all set explicitly rather than relying on the platform's — several of
        // these defaults have changed across API levels and minSdk here is 26.
        settings.apply {
            javaScriptEnabled = JAVASCRIPT_ENABLED

            // A page must not be able to read the filesystem or the app's private
            // directory. The last two are the ones that matter most: they are what
            // let a file:// document treat every other file as same-origin.
            allowFileAccess = false
            allowContentAccess = false
            allowFileAccessFromFileURLs = false
            allowUniversalAccessFromFileURLs = false

            // No location prompt from a third-party page. There is no
            // onGeolocationPermissionsShowPrompt override either, so a request
            // is denied rather than silently granted.
            setGeolocationEnabled(false)

            // A page may not start audio or video on its own.
            mediaPlaybackRequiresUserGesture = true

            // No http subresources inside an https page, and no "compatibility"
            // middle setting. MIXED_CONTENT_COMPATIBILITY_MODE loads http images
            // and media, which is enough for a network attacker to fingerprint
            // and to inject.
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW

            safeBrowsingEnabled = true

            // Not in the baseline, and worth adding: a page must not be able to
            // open more WebViews. Without this, window.open() and
            // target="_blank" go through onCreateWindow, and a chrome client that
            // handles that has to make its own hardening decisions — a second
            // WebView with default settings is the classic way this baseline gets
            // bypassed without anyone editing this file.
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
        }

        // Debug builds only, gated on this module's own BuildConfig. Left on in a
        // release build it exposes the WebView's contents to any app that can talk
        // to the device's debug bridge.
        if (BuildConfig.DEBUG) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        webViewClient = object : WebViewClient() {

            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest,
            ): Boolean {
                val target = request.url?.toString()
                // Trust is re-derived from the page currently loaded, not from an
                // argument, so this cannot drift out of step with the URL bar.
                //
                // `view.url` is the MAIN FRAME's URL, and this callback fires for
                // subframe navigations too — so the frame is passed alongside the
                // trust rather than left implicit (BIT-58). Without it, a
                // cross-origin <iframe> on a getbittr.com page would be judged
                // with getbittr.com's trust, which is the residual gap in the iOS
                // fix this port is not repeating. WebsiteNavigationPolicy.decide
                // demotes a subframe to ThirdParty; the demotion lives there, with
                // the tests, rather than here where it reads as a detail.
                val trust = FirstPartyOrigins.trustOf(view.url)
                val decision = WebsiteNavigationPolicy.decide(
                    url = target,
                    trust = trust,
                    isForMainFrame = request.isForMainFrame,
                )
                return when (decision) {
                    // Returning true means "the app handled it" — and the app's
                    // handling of a dropped navigation is to do nothing at all.
                    // No dialog, no intent, no handler, no network call (R-2).
                    is NavigationDecision.Drop -> true
                    NavigationDecision.Load -> false
                }
            }

            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                // R-10: navigating away supersedes anything in flight, so a
                // response cannot arrive against the page that has just gone.
                lnurlSlot.cancel()
                onPageUrlChanged(url)
            }

            override fun onPageFinished(view: WebView, url: String?) {
                onPageUrlChanged(url)
            }

            /**
             * Always cancel, and never `handler.proceed()` — and no "load anyway"
             * prompt either, since a prompt is just `proceed()` with a step in
             * front of it. A user cannot evaluate a certificate chain, and this
             * browser exists to show three static pages, a block explorer and
             * merchant sites, none of which have a reason to present a bad
             * certificate.
             *
             * `WebViewHardeningGuardTest` asserts that `proceed()` is absent from
             * this file's *code*; it strips comments first, which is why this one
             * can name the call rather than talking around it.
             */
            override fun onReceivedSslError(
                view: WebView,
                handler: SslErrorHandler,
                error: SslError,
            ) {
                handler.cancel()
            }
        }

        webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                onProgress(newProgress)
            }
        }
    }
}
