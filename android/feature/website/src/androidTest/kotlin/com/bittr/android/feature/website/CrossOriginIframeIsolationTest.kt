package com.bittr.android.feature.website

import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bittr.android.core.lnurl.LnurlRequestSlot
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * BIT-58 §Definition of done 2.
 *
 * A page containing a **cross-origin `<iframe>`** which tries to reach the wallet
 * from inside that iframe. The wallet does not react.
 *
 * ### Why this test exists separately from [ThirdPartyIsolationTest]
 *
 * That test loads a hostile page as the **main frame**, which is the case an
 * origin gate is built to catch. This one is the case an origin gate *misses*:
 *
 * > An origin gate reasons about *the page*; a JS bridge is exposed per *frame*.
 *
 * On iOS, `WKUserContentController.add(_:name:)` exposes the handler in every
 * frame, `forMainFrameOnly:` constrains only the injected script, and the gate
 * reads `webView.url` — the main frame's. So an iframe on a first-party page
 * passes it. On Android the same shape is worse, because
 * `addJavascriptInterface` has no frame scoping at all and no per-frame check is
 * available on the injected object.
 *
 * The Bittr Android build has no bridge of any kind, so it is immune to both —
 * and **this test is what makes that a checked property instead of a claim.** If
 * someone later adds `addJavascriptInterface`, the probe below finds the object
 * in the iframe and this test goes red, which is precisely the regression a
 * `webView.url` origin check would have waved through.
 *
 * ### What stands in for `https://getbittr.com`
 *
 * The test cannot serve the real first-party origin, so the parent page is on
 * loopback. That does not weaken what is being asserted, because the two halves
 * of the requirement are checked where each is actually decidable:
 *
 * - **"No frame exposes a bridge"** is a property of the WebView's
 *   configuration, not of the origin it happens to be showing. No
 *   `addJavascriptInterface` and no `addWebMessageListener` call exists in
 *   `android/` at all (`JavascriptInterfaceGuardTest`,
 *   `WebViewBridgeOriginGuardTest`), so the object is absent in every frame of
 *   every page — which is what this test observes directly, in an iframe.
 * - **"A subframe is not judged with the main frame's trust"** is decided by
 *   [WebsiteNavigationPolicy], and is asserted against a genuinely first-party
 *   `WebsiteTrust.FirstParty` value in `WebsiteNavigationPolicyTest`.
 *
 * ### Cross-origin, on loopback
 *
 * Two [LocalTestServer]s. An origin is scheme + host + **port**, so
 * `http://127.0.0.1:41001` and `http://127.0.0.1:41002` are as cross-origin to
 * each other as two unrelated domains are — the same-origin policy does not
 * treat loopback specially. The iframe's script therefore runs in a genuinely
 * separate origin from its parent, which is the condition under test.
 */
@RunWith(AndroidJUnit4::class)
class CrossOriginIframeIsolationTest {

    private lateinit var parentServer: LocalTestServer
    private lateinit var iframeServer: LocalTestServer
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private companion object {
        /** Real `lnurl1…`, decoding to `https://127.0.0.1/lnurlp/abc`. */
        const val LNURL =
            "lnurl1dp68gurn8ghj7vfjxuhrqt3s9ccj7mrww4excup0v93xx5vnq97"

        const val LNURL_ENDPOINT_PATH = "/lnurlp/abc"
        const val PARENT_PATH = "/parent.html"
        const val IFRAME_PATH = "/iframe.html"

        const val LOAD_TIMEOUT_SECONDS = 20L

        /** Time given to the iframe to misbehave after the parent has loaded. */
        const val MISBEHAVE_MILLIS = 3_000L
    }

    /**
     * The parent page. It is not hostile itself — it stands in for a first-party
     * page that embeds third-party content, which is the ordinary, entirely
     * normal thing a real page does and the reason this hole is reachable
     * without compromising the first party at all.
     *
     * It listens for the iframe's report and parks it on `window.__bittrIframe`,
     * because `evaluateJavascript` runs in the main frame and cannot read the
     * iframe's variables directly.
     */
    private fun parentPage(iframeOrigin: String) = """
        <!doctype html><html><body>
        <h1>first-party page</h1>
        <script>
          window.__bittrIframe = null;
          window.addEventListener('message', function (e) {
            // Whatever the iframe managed to find, recorded verbatim.
            window.__bittrIframe = e.data;
          });
        </script>
        <iframe id="child" src="$iframeOrigin$IFRAME_PATH"></iframe>
        </body></html>
    """.trimIndent()

    /**
     * The iframe. Cross-origin to its parent, and it tries every channel the iOS
     * gap would have handed it:
     *
     * - `webkit.messageHandlers.lnurl` — the iOS handler, present in every frame.
     * - the names an `addJavascriptInterface` port would plausibly have used.
     * - **any** own property of `window` carrying a `postMessage` — the catch-all
     *   for a bridge injected under a name this test does not know. `parent`,
     *   `top` and the window's other aliases are excluded by identity, because
     *   `postMessage` on a `Window` is the DOM API and is not a bridge.
     * - a `lightning:` navigation of its own frame, which reaches
     *   `shouldOverrideUrlLoading` with `isForMainFrame = false`.
     * - a `lightning:` navigation of **top**, which is the escalation an iframe
     *   attempts when its own frame gets it nowhere.
     *
     * It deliberately does **not** fetch the LNURL endpoint itself: the server's
     * request log is the evidence that *the wallet* made no call, and a fetch
     * from the page would poison it.
     */
    private fun iframePage() = """
        <!doctype html><html><body>
        <script>
          var report = { ran: true, bridges: [], errors: [], topNavigated: false };

          function note(name, present) { if (present) report.bridges.push(name); }

          try {
            note('webkit.messageHandlers.lnurl',
                 !!(window.webkit && window.webkit.messageHandlers &&
                    window.webkit.messageHandlers.lnurl));

            ['bittrLnurl', 'Android', 'AndroidBridge', 'lnurl', 'BittrBridge', 'bittr']
              .forEach(function (n) {
                note(n, typeof window[n] === 'object' || typeof window[n] === 'function');
              });

            // By identity, not by name — see the same block in
            // ThirdPartyIsolationTest. That version listed these by name, missed
            // `frames`, and reported the window itself as a bridge on the first
            // run it ever got. A name list also cannot exclude an alias it has
            // not heard of, while still needing to admit a bridge under a name
            // it has not heard of, which is the wrong way round.
            var selfAliases = [];
            ['self', 'frames', 'parent', 'top', 'opener'].forEach(function (n) {
              try { if (window[n]) selfAliases.push(window[n]); } catch (e) {}
            });
            selfAliases.push(window);
            function isSelfAlias(v) {
              for (var i = 0; i < selfAliases.length; i++) {
                try { if (v === selfAliases[i]) return true; } catch (e) {}
              }
              return false;
            }

            for (var key in window) {
              try {
                var v = window[key];
                if (v && typeof v.postMessage === 'function' && !isSelfAlias(v)) {
                  report.bridges.push('postMessage:' + key);
                  // Use it, so that a bridge which exists but is never called
                  // cannot be argued to be harmless.
                  v.postMessage('lightning:$LNURL');
                }
              } catch (e) { /* cross-origin accessors throw; not a bridge */ }
            }
          } catch (e) { report.errors.push(String(e)); }

          // Report before navigating: a navigation that did succeed would tear
          // this frame down, and the report would never be sent.
          try { window.parent.postMessage(report, '*'); } catch (e) {}

          setTimeout(function () {
            // This frame.
            try { window.location.href = 'lightning:$LNURL'; } catch (e) {}
            // The top frame — the escalation.
            try { window.top.location.href = 'lightning:$LNURL'; } catch (e) {}
            try { window.parent.postMessage(report, '*'); } catch (e) {}
          }, 200);
        </script>
        </body></html>
    """.trimIndent()

    @Before
    fun startServers() {
        iframeServer = LocalTestServer()
        iframeServer.start(mapOf(IFRAME_PATH to iframePage()))

        parentServer = LocalTestServer()
        parentServer.start(
            mapOf(
                PARENT_PATH to parentPage(iframeServer.origin),
                // Present so a request would succeed. The assertion is that it is
                // never asked for, and a 404 would muddy that.
                LNURL_ENDPOINT_PATH to
                    """{"tag":"payRequest","callback":"${parentServer.origin}/cb",""" +
                    """"minSendable":1000000,"maxSendable":1000000}""",
            ),
        )
    }

    @After
    fun stopServers() {
        parentServer.stop()
        iframeServer.stop()
    }

    /** Builds the real hardened WebView, loads the parent page, waits, returns it. */
    private fun loadParentPage(): WebView {
        val loaded = CountDownLatch(1)
        lateinit var webView: WebView

        instrumentation.runOnMainSync {
            webView = HardenedWebView.create(
                context = instrumentation.targetContext,
                onProgress = { if (it == 100) loaded.countDown() },
                onPageUrlChanged = { },
                lnurlSlot = LnurlRequestSlot(),
            )
            webView.loadUrl(parentServer.origin + PARENT_PATH)
        }

        assertTrue(
            "The parent page never finished loading, so nothing below was actually " +
                "exercised. A test that cannot load its own fixture must fail, not pass.",
            loaded.await(LOAD_TIMEOUT_SECONDS, TimeUnit.SECONDS),
        )

        Thread.sleep(MISBEHAVE_MILLIS)
        instrumentation.waitForIdleSync()
        return webView
    }

    /** Runs [script] in the **main frame** and returns its result as a JSON string. */
    private fun evaluate(webView: WebView, script: String): String {
        val done = CountDownLatch(1)
        var result = ""
        instrumentation.runOnMainSync {
            webView.evaluateJavascript(script) { value ->
                result = value
                done.countDown()
            }
        }
        assertTrue(
            "evaluateJavascript did not return within 10s",
            done.await(10, TimeUnit.SECONDS),
        )
        return result
    }

    // --- The test that would have caught the iOS gap ------------------------------

    @Test
    fun theCrossOriginIframeActuallyRan() {
        // Checked first and on its own, because every other assertion in this file
        // is vacuous if the iframe never loaded. "No bridge was found" and "the
        // iframe never got to look" produce the same green tick otherwise, and the
        // second one is worthless.
        val webView = loadParentPage()

        val ran = evaluate(webView, "JSON.stringify(!!(window.__bittrIframe || {}).ran)")

        assertEquals(
            "The cross-origin iframe did not report in, so this test proved nothing. " +
                "Check that the second LocalTestServer is reachable and that the " +
                "iframe document loaded — not that the wallet is safe.",
            "\"true\"",
            ran,
        )
    }

    @Test
    fun aCrossOriginIframeFindsNoBridgeToPostTo() {
        val webView = loadParentPage()

        val bridges = evaluate(
            webView,
            "JSON.stringify(((window.__bittrIframe || {}).bridges) || ['<no report>'])",
        )

        assertEquals(
            "A cross-origin iframe on a first-party page must find no bridge object " +
                "(BIT-58 DoD 1). This is the case a webView.url origin gate does not " +
                "catch: the gate sees the main frame's first-party URL and lets the " +
                "iframe through. Android has no frame scoping on " +
                "addJavascriptInterface at all, so the only safe answer is that no " +
                "bridge object exists in any frame. Found: $bridges",
            "\"[]\"",
            bridges,
        )
    }

    @Test
    fun aCrossOriginIframeCannotNavigateTheTopFrameToALightningUrl() {
        val webView = loadParentPage()

        var currentUrl: String? = null
        instrumentation.runOnMainSync { currentUrl = webView.url }

        assertEquals(
            "The iframe set window.top.location to a lightning: URL. The main frame " +
                "must still be on the page it loaded: the navigation is cancelled and " +
                "dropped (R-2), so it does not become the current URL and it does not " +
                "leave the app.",
            parentServer.origin + PARENT_PATH,
            currentUrl,
        )
    }

    @Test
    fun aCrossOriginIframeTriggersNoNetworkCallToAnLnurlEndpoint() {
        loadParentPage()

        val lnurlRequests = (parentServer.requestedPaths + iframeServer.requestedPaths)
            .filter { it.startsWith(LNURL_ENDPOINT_PATH) || it.startsWith("/cb") }

        assertEquals(
            "No LNURL endpoint may be contacted on behalf of an iframe (R-8). The " +
                "iframe navigated to lightning:$LNURL in its own frame and in top; " +
                "both are dropped, so nothing fetches the payRequest.\n" +
                "Parent server saw: ${parentServer.requestedPaths}\n" +
                "Iframe server saw: ${iframeServer.requestedPaths}",
            emptyList<String>(),
            lnurlRequests,
        )
    }
}
