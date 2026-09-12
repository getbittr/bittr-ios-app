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
 * BIT-33 §Acceptance 3 and 4.
 *
 * A page on a non-allowlisted origin that **posts to a message listener** and
 * **navigates to `lightning:lnurl1…`** produces no wallet flow, no dialog and no
 * network call — and cannot trigger LNURL-auth either.
 *
 * ### Why this is instrumented and not a Robolectric test
 *
 * Robolectric's `WebView` is a shadow with no renderer and no JavaScript engine.
 * It cannot run the hostile page, so it would report success without having
 * loaded it — which is worse than not testing, because the green tick would be
 * mistaken for evidence. These need a real WebView, so they need a device or an
 * emulator.
 *
 * ### What "no network call" is measured against
 *
 * [LocalTestServer] records every path it is asked for and exposes an
 * `/lnurlp/…` route that a working LNURL flow would fetch. The assertion is that
 * the route is never requested. An assertion with nothing on the other end of it
 * would pass in a world where the bridge existed and simply used a different
 * host.
 *
 * (The ellipsis above is not decoration: Kotlin block comments **nest**, so a
 * literal `*` after a slash inside KDoc opens a comment that the closing
 * delimiter then consumes, and the file stops compiling at its last line.)
 */
@RunWith(AndroidJUnit4::class)
class ThirdPartyIsolationTest {

    private lateinit var server: LocalTestServer
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private companion object {
        /** Real `lnurl1…`, decoding to `https://127.0.0.1/lnurlp/abc`. */
        const val LNURL =
            "lnurl1dp68gurn8ghj7vfjxuhrqt3s9ccj7mrww4excup0v93xx5vnq97"

        const val LNURL_ENDPOINT_PATH = "/lnurlp/abc"
        const val AUTH_PATH = "/auth"
        const val PAGE_PATH = "/hostile.html"

        /** The same hostile page, but with a bridge deliberately planted in it. */
        const val PLANTED_PAGE_PATH = "/planted.html"

        /**
         * A bridge-shaped object, planted from JavaScript before the probe runs.
         *
         * **It must not be planted with `addJavascriptInterface`.** That API is
         * banned repo-wide by `JavascriptInterfaceGuardTest`, which scans every
         * Kotlin file under `android/` — this one included — and has deliberately
         * no allowlist. The scan strips string literals, so a bridge built *in
         * the page* is both invisible to it and, more to the point, not actually
         * a bridge: nothing native is exposed and the wallet is not modified.
         *
         * That makes this a test of the probe, not of the app, which is exactly
         * what it is for. The probe's rule is
         * `typeof v.postMessage === 'function' && !isSelfAlias(v)`, and a real
         * `addJavascriptInterface` object reaches that rule the same way this one
         * does: as an enumerable own property of `window` that is not the window.
         */
        const val PLANTED_BRIDGE = """
            window.bittrLnurl = {
              postMessage: function (m) {
                (window.__bittrPlanted = window.__bittrPlanted || []).push(String(m));
              }
            };
        """

        val LOAD_TIMEOUT_SECONDS = 20L

        /** Time given to the page to misbehave after it has loaded. */
        val MISBEHAVE_MILLIS = 2_000L
    }

    /**
     * The page. It tries every channel iOS's WebView would have offered it:
     *
     * - `webkit.messageHandlers.lnurl.postMessage` — the iOS handler by name.
     * - `bittrLnurl` / `Android` / `AndroidBridge` — the names an
     *   `addJavascriptInterface` port would plausibly have used.
     * - a `lightning:` navigation, both by `location.href` and by clicking an
     *   anchor, because those take different paths through the WebView.
     * - a `tag=login` auth URL, which iOS's `decidePolicyFor` matches on substring.
     * - an anchor whose href merely contains `lnurl`, which iOS's injected
     *   `MutationObserver` posts to the native handler.
     *
     * It records what it found in `window.__bittrProbe` so the test can read back
     * whether any bridge object was present, rather than inferring it from the
     * absence of an effect.
     */
    private fun hostilePage(origin: String, plant: String = "") = """
        <!doctype html><html><body>
        <a id="lnurlLink" href="lightning:$LNURL">pay</a>
        <a id="substringLink" href="https://example.invalid/?utm=lnurl">not an lnurl</a>
        <a id="authLink" href="$origin$AUTH_PATH?tag=login&k1=${"ab".repeat(32)}">log in</a>
        <script>
          $plant
          window.__bittrProbe = { bridges: [], errors: [] };
          function note(name, present) { if (present) window.__bittrProbe.bridges.push(name); }

          try {
            note('webkit.messageHandlers.lnurl',
                 !!(window.webkit && window.webkit.messageHandlers &&
                    window.webkit.messageHandlers.lnurl));
            ['bittrLnurl', 'Android', 'AndroidBridge', 'lnurl', 'BittrBridge']
              .forEach(function (n) { note(n, typeof window[n] === 'object' ||
                                             typeof window[n] === 'function'); });

            // Try to use them anyway, in case one exists under a name not listed.
            //
            // `postMessage` is a DOM method on every Window, and `for…in` walks
            // Window.prototype, so the window turns up here under each of its own
            // aliases — `window`, `self`, `frames`, `parent`, `top`. None is a
            // bridge. They are excluded by *identity* rather than by name: a name
            // list is what broke this test the first time it ever ran (it listed
            // four of the five and `frames` walked straight through), and a name
            // list is also the thing a bridge injected under an unexpected name
            // would slip past — which is the entire reason for this catch-all.
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
                  window.__bittrProbe.bridges.push('postMessage:' + key);
                  v.postMessage('lightning:$LNURL');
                }
              } catch (e) { /* cross-origin accessors throw; not a bridge */ }
            }
          } catch (e) { window.__bittrProbe.errors.push(String(e)); }

          // A MutationObserver, exactly as iOS injects one, in case the port kept it.
          new MutationObserver(function () {}).observe(document.body,
              { childList: true, subtree: true });
          document.body.appendChild(document.createElement('span'));

          // Navigation attempts, on a delay so the page has committed first.
          setTimeout(function () {
            try { document.getElementById('lnurlLink').click(); } catch (e) {}
            try { document.getElementById('authLink').click(); } catch (e) {}
            try { window.location.href = 'lightning:$LNURL'; } catch (e) {}
            try { window.location.href = 'lnurlp://127.0.0.1$LNURL_ENDPOINT_PATH'; } catch (e) {}
          }, 100);
        </script>
        </body></html>
    """.trimIndent()

    @Before
    fun startServer() {
        server = LocalTestServer()
        server.start(
            mapOf(
                PAGE_PATH to hostilePage(server.origin),
                PLANTED_PAGE_PATH to hostilePage(server.origin, PLANTED_BRIDGE),
                // Present so that a request to them would succeed — the assertion
                // is that they are never asked for, and a 404 would muddy that.
                LNURL_ENDPOINT_PATH to
                    """{"tag":"payRequest","callback":"${server.origin}/cb",""" +
                    """"minSendable":1000000,"maxSendable":1000000}""",
                AUTH_PATH to "{}",
            ),
        )
    }

    @After
    fun stopServer() {
        server.stop()
    }

    /** Builds the real hardened WebView, loads the hostile page, waits, returns it. */
    private fun loadHostilePage(path: String = PAGE_PATH): WebView {
        val loaded = CountDownLatch(1)
        lateinit var webView: WebView

        instrumentation.runOnMainSync {
            webView = HardenedWebView.create(
                context = instrumentation.targetContext,
                onProgress = { if (it == 100) loaded.countDown() },
                onPageUrlChanged = { },
                lnurlSlot = LnurlRequestSlot(),
            )
            webView.loadUrl(server.origin + path)
        }

        assertTrue(
            "The hostile page never finished loading, so nothing below was actually " +
                "exercised. A test that cannot load its own fixture must fail, not pass.",
            loaded.await(LOAD_TIMEOUT_SECONDS, TimeUnit.SECONDS),
        )

        Thread.sleep(MISBEHAVE_MILLIS)
        instrumentation.waitForIdleSync()
        assertFixtureRan(webView)
        return webView
    }

    /**
     * Fails unless the fixture's own script actually executed.
     *
     * Progress reaching 100 is not that assertion, which is the point of this
     * one. A WebView that refuses a URL — `ERR_CLEARTEXT_NOT_PERMITTED` being the
     * one this suite is most likely to hit, since the fixtures are served over
     * http on loopback — renders an *error page*, and an error page finishes
     * loading and reports 100% just as a real page does.
     *
     * Every assertion in this class is of the form "the hostile page did not
     * manage to X". A page that never ran did not manage to X either, so without
     * this the whole class goes green while testing nothing at all — the precise
     * failure mode that makes a security test worse than no test, because it also
     * reports success. `window.__bittrProbe` is set on the fixture's first script
     * line and exists nowhere else, so its presence is proof the page is the one
     * that was asked for and that its JavaScript ran.
     */
    private fun assertFixtureRan(webView: WebView) {
        val marker = evaluate(webView, "typeof window.__bittrProbe")

        assertEquals(
            "The hostile fixture's script did not run, so every assertion in this " +
                "class would pass without exercising anything. The usual cause is the " +
                "page not actually loading — cleartext to 127.0.0.1 is permitted only " +
                "by src/androidTest/res/xml/network_security_config_test.xml, and " +
                "without it the WebView shows an error page that still reports 100% " +
                "progress. Current URL: ${urlOf(webView)}",
            "\"object\"",
            marker,
        )
    }

    /** [WebView.getUrl] read on the main thread, for failure messages. */
    private fun urlOf(webView: WebView): String? {
        var url: String? = null
        instrumentation.runOnMainSync { url = webView.url }
        return url
    }

    /** Runs [script] in the page and returns its result as a JSON string. */
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

    // --- §Acceptance 3 ----------------------------------------------------------

    @Test
    fun aThirdPartyPageFindsNoBridgeToPostTo() {
        val webView = loadHostilePage()

        val bridges = evaluate(webView, "JSON.stringify(window.__bittrProbe.bridges)")

        assertEquals(
            "A page on a non-allowlisted origin must find no bridge object at all. " +
                "The page probes for the iOS handler by name, for the names an " +
                "addJavascriptInterface port would use, and for any window property " +
                "with a postMessage method. Found: $bridges",
            "\"[]\"",
            bridges,
        )
    }

    @Test
    fun aThirdPartyPageCannotNavigateToALightningUrl() {
        val webView = loadHostilePage()

        var currentUrl: String? = null
        instrumentation.runOnMainSync { currentUrl = webView.url }

        assertEquals(
            "The WebView must still be on the page it loaded. A lightning: navigation " +
                "is cancelled and dropped (R-2), so it changes nothing — it does not " +
                "become the current URL and it does not leave the app.",
            server.origin + PAGE_PATH,
            currentUrl,
        )
    }

    @Test
    fun aThirdPartyPageTriggersNoNetworkCallToAnLnurlEndpoint() {
        loadHostilePage()

        val lnurlRequests = server.requestedPaths.filter {
            it.startsWith(LNURL_ENDPOINT_PATH) || it.startsWith("/cb")
        }

        assertEquals(
            "No LNURL endpoint may be contacted (R-8). The page navigated to " +
                "lightning:$LNURL and to lnurlp://…$LNURL_ENDPOINT_PATH; both are " +
                "dropped, so nothing fetches the payRequest. Requests seen: " +
                "${server.requestedPaths}",
            emptyList<String>(),
            lnurlRequests,
        )
    }

    // --- The probe's own positive control ----------------------------------------

    /**
     * The probe reports a bridge when one is there.
     *
     * Every other bridge assertion in this file and in
     * [CrossOriginIframeIsolationTest] is an assertion that a list came back
     * **empty**, and an empty list is what a probe that has quietly stopped
     * working returns too. `theCrossOriginIframeActuallyRan` closes half of that
     * hole — it proves the iframe loaded and reported in. It does not prove the
     * probe inside it can still recognise a bridge.
     *
     * This closes the other half, and it guards a specific, recent near-miss.
     * The catch-all used to exclude the window's frame-tree aliases *by name*,
     * missed `frames`, and reported the page's own DOM API as a wallet bridge on
     * the first run it was ever given (run 68). The fix swapped the name list for
     * exclusion by identity — which is the right shape, and is also one `!` away
     * from excluding everything and passing forever. Nothing in the suite would
     * have noticed. This test would.
     *
     * Both halves of the probe are checked, because they fail independently: the
     * name list (`bittrLnurl`) and the `for…in` catch-all
     * (`postMessage:bittrLnurl`). The catch-all is the one that matters, since it
     * is the only half that can catch a bridge added under a name nobody
     * predicted, and it is the half the identity change rewrote.
     */
    @Test
    fun theBridgeProbeReportsABridgeThatIsActuallyThere() {
        val webView = loadHostilePage(PLANTED_PAGE_PATH)

        val bridges = evaluate(webView, "JSON.stringify(window.__bittrProbe.bridges)")

        assertTrue(
            "The probe's name list did not report a planted window.bittrLnurl. That " +
                "list is the half of the probe that checks for the names an " +
                "addJavascriptInterface port would plausibly have used, so the other " +
                "tests in this file are not evidence of anything while it is broken. " +
                "Found: $bridges",
            "bittrLnurl" in bridges,
        )

        assertTrue(
            "The probe's for…in catch-all did not report a planted bridge. This is " +
                "the half that finds a bridge injected under a name this test does " +
                "not know, which is the whole reason it exists — a name list cannot " +
                "catch what it has not heard of. It excludes the window's own aliases " +
                "by identity; if that exclusion has widened to cover everything, every " +
                "other bridge assertion here passes vacuously and this is the only " +
                "test that fails. Found: $bridges",
            "postMessage:bittrLnurl" in bridges,
        )

        val delivered = evaluate(webView, "JSON.stringify(window.__bittrPlanted || [])")

        assertTrue(
            "The probe found the planted bridge but never posted to it. The catch-all " +
                "calls postMessage on what it finds, so that a bridge which exists but " +
                "is never exercised cannot be argued to be harmless — and the other " +
                "tests rely on that call having been attempted. Delivered: $delivered",
            "lightning:" in delivered,
        )
    }

    // --- §Acceptance 4 ----------------------------------------------------------

    @Test
    fun aThirdPartyPageCannotTriggerLnurlAuth() {
        val webView = loadHostilePage()

        // The page clicks an anchor whose href carries tag=login and a well-formed
        // 32-byte k1 — the exact shape iOS's decidePolicyFor matches on substring
        // and routes into the wallet's signing path.
        //
        // Two things must hold. The auth URL is http(s), so unlike the lightning:
        // link it is a *loadable* navigation: the page is allowed to browse to it,
        // and doing so is just a page load. What must not happen is the wallet
        // treating it as an auth request. Nothing in this module can — there is no
        // bridge and no navigation interception — so the check is that no LNURL
        // machinery exists on the third-party path at all.
        val bridges = evaluate(webView, "JSON.stringify(window.__bittrProbe.bridges)")

        assertEquals(
            "A tag=login URL on a third-party page must reach nothing. Found bridges: " +
                bridges,
            "\"[]\"",
            bridges,
        )

        assertTrue(
            "The WebView must not have handed the auth URL anywhere — it either stayed " +
                "on the hostile page or simply browsed to the auth path as an ordinary " +
                "page. What it must not do is leave the app or start a wallet flow. " +
                "Requests seen: ${server.requestedPaths}",
            server.requestedPaths.none { it.startsWith("/cb") },
        )
    }

    // --- The hardening baseline, on the real object ------------------------------

    @Test
    fun theHardeningBaselineIsAppliedToTheRealWebView() {
        // The :app guard test checks the source text. This checks the object, which
        // is the half that would catch a setting being applied and then overwritten.
        lateinit var webView: WebView
        instrumentation.runOnMainSync {
            webView = HardenedWebView.create(
                context = instrumentation.targetContext,
                onProgress = { },
                onPageUrlChanged = { },
                lnurlSlot = LnurlRequestSlot(),
            )
        }

        instrumentation.runOnMainSync {
            val settings = webView.settings
            assertEquals(false, settings.allowFileAccess)
            assertEquals(false, settings.allowContentAccess)
            assertEquals(false, settings.allowFileAccessFromFileURLs)
            assertEquals(false, settings.allowUniversalAccessFromFileURLs)
            assertEquals(true, settings.mediaPlaybackRequiresUserGesture)
            assertEquals(
                android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW,
                settings.mixedContentMode,
            )
            assertEquals(true, settings.safeBrowsingEnabled)
            assertEquals(false, settings.javaScriptCanOpenWindowsAutomatically)
        }
    }
}
