package com.bittr.android

import com.bittr.android.SourceTree.code
import com.bittr.android.SourceTree.codeWithoutLiterals
import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Every `WebView` in the app is built by one function, with one set of settings
 * (BIT-33 R-11).
 *
 * ### Why routing matters more than the settings themselves
 *
 * R-11 lists nine `WebSettings` values and three other rules, and applies them to
 * "both WebViews". Writing them once is easy. Keeping them is the problem: the
 * next WebView is added by someone porting a different screen, and a
 * `WebView(context)` with platform defaults has `allowFileAccess = true`,
 * `mixedContentMode = MIXED_CONTENT_ALLOW` on older targets, and an
 * `onReceivedSslError` that does nothing — which means the error is *ignored* and
 * the page loads over a broken certificate.
 *
 * So the enforceable version of "the baseline applies to both WebViews" is that
 * there is only one place a WebView can come from. This test checks that, and
 * checks the baseline is actually in that place.
 *
 * A second WebView is fine — call `HardenedWebView.create`. What is not fine is a
 * second *configuration*.
 *
 * ### The rule is about construction and configuration, not about the type
 *
 * This check first banned the *name* `android.webkit.WebView` outside the
 * factory, which is not the same rule and is wrong in both directions. It flagged
 * `ThirdPartyIsolationTest`, whose whole job is to call the factory and then
 * assert the baseline on the object it returns — the strongest evidence the app
 * has that the settings are really applied, reported as a violation. The way out
 * of a false positive is a name on an allowlist, and a file on that allowlist can
 * then configure a WebView freely, which is the rule inverting itself.
 *
 * So what is banned is the constructor, the two client classes, and assignment
 * into `settings`. Holding a `WebView`, passing one and reading its settings are
 * all fine, because none of them can produce an unhardened one.
 */
class WebViewHardeningGuardTest {

    private companion object {
        const val FACTORY_FILE = "HardenedWebView.kt"

        /**
         * Ways to get a WebView that did not come from the factory, or to change
         * one after it did. Matched against code with comments and string
         * literals removed.
         */
        val BANNED_PATTERNS = mapOf(
            // `WebView(context)`. The lookbehind keeps `HardenedWebView.create(`
            // and a declared return type of `WebView` out of it — only a call
            // with the bare name matches.
            "a WebView constructor call" to
                Regex("""(?<![A-Za-z0-9_.])WebView\s*\("""),

            // A client is where the navigation, SSL and page-lifecycle decisions
            // live. A second one is a second set of them, and `onReceivedSslError`
            // is the specific override that turns a certificate error into a
            // silently loaded page.
            //
            // The bare name is banned rather than a `object : WebViewClient()`
            // shape, because the shape can be spread over two lines and because
            // nothing outside the factory has a reason to name these types at all
            // — unlike `WebView` and `WebSettings`, which a test legitimately
            // holds and reads.
            "the WebViewClient type" to Regex("""\bWebViewClient\b"""),
            "the WebChromeClient type" to Regex("""\bWebChromeClient\b"""),

            // Writing a setting, anywhere but the factory. Reading one is how the
            // instrumented test proves the baseline holds on the real object, so
            // only assignment and the bulk forms are matched.
            "a WebSettings assignment" to
                Regex("""\bsettings\s*\.\s*\w+\s*=(?!=)"""),
            "a WebSettings configuration block" to
                Regex("""\bsettings\s*\.\s*(apply|run|also)\s*\{"""),
            "a WebSettings setter call" to
                Regex("""\bsettings\s*\.\s*set[A-Z]\w*\s*\("""),
        )

        val ALLOWED_FILES = setOf(
            FACTORY_FILE,
            "WebViewHardeningGuardTest.kt",
        )

        /**
         * The R-11 baseline, as `setting to expected value`. Checked as source
         * text: the alternative is instantiating a WebView under Robolectric,
         * whose `WebSettings` is a shadow that records whatever it is handed and
         * would therefore agree with any diff that stopped calling these.
         */
        val REQUIRED_SETTINGS = listOf(
            "allowFileAccess = false",
            "allowContentAccess = false",
            "allowFileAccessFromFileURLs = false",
            "allowUniversalAccessFromFileURLs = false",
            "setGeolocationEnabled(false)",
            "mediaPlaybackRequiresUserGesture = true",
            "mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW",
            "safeBrowsingEnabled = true",
            // Not in R-11's list. Added because window.open() and target="_blank"
            // otherwise route through onCreateWindow, and the second WebView that
            // handles them is the standard way this baseline gets bypassed
            // without this file being touched.
            "javaScriptCanOpenWindowsAutomatically = false",
            "setSupportMultipleWindows(false)",
        )
    }

    @Test
    fun `WebViews are only created and configured in one file`() {
        val offenders = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .mapNotNull { file ->
                val code = file.codeWithoutLiterals()
                val hit = BANNED_PATTERNS.entries
                    .firstOrNull { (_, pattern) -> pattern.containsMatchIn(code) }
                    ?: return@mapNotNull null
                "${file.repoPath()} (${hit.key})"
            }

        assertTrue(
            "WebViews must be created through HardenedWebView.create, which applies the " +
                "BIT-33 R-11 hardening baseline. A WebView built anywhere else starts from " +
                "platform defaults — file access on, and an onReceivedSslError that IGNORES " +
                "certificate errors rather than cancelling them.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "Adding a second WebView is fine; adding a second configuration is not. " +
                "Call the factory. Holding a WebView the factory returned, passing one, and " +
                "reading its settings are all allowed — none of them can produce an " +
                "unhardened one.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the hardening baseline is present in the factory`() {
        // Code, not raw text: a setting named only in the KDoc above the block
        // would otherwise satisfy this, and the KDoc does discuss several of them.
        val source = SourceTree.kotlinSources().single { it.name == FACTORY_FILE }.code()

        val missing = REQUIRED_SETTINGS.filterNot { it in source }

        assertTrue(
            "$FACTORY_FILE must apply the whole BIT-33 R-11 hardening baseline. Missing:\n  " +
                missing.joinToString("\n  ") + "\n" +
                "These are set explicitly rather than left to the platform because several " +
                "of the defaults differ by API level and minSdk here is 26.",
            missing.isEmpty(),
        )
    }

    @Test
    fun `SSL errors are cancelled and never proceeded`() {
        // Code, so the factory's KDoc is free to name the call it must never make.
        // It previously had to avoid writing `proceed()` even while explaining why
        // it does not call it, with a comment asking the next reader not to quote
        // it either — a check that constrains the documentation rather than the
        // behaviour is the wrong shape.
        val source = SourceTree.kotlinSources().single { it.name == FACTORY_FILE }.code()

        assertTrue(
            "$FACTORY_FILE must override onReceivedSslError and call handler.cancel() " +
                "(BIT-33 R-11). Not overriding it at all is the dangerous case: the default " +
                "implementation cancels, but a WebViewClient that forgets it alongside a " +
                "proceed() elsewhere is how this goes wrong.",
            "onReceivedSslError" in source && "handler.cancel()" in source,
        )

        assertTrue(
            "$FACTORY_FILE must never call handler.proceed() on an SSL error, and must not " +
                "offer the user a 'continue anyway' choice. A user cannot evaluate a " +
                "certificate chain, and this browser shows three static pages, a block " +
                "explorer and merchant sites — none of which have a reason to present a bad " +
                "certificate.",
            "proceed()" !in source,
        )
    }

    @Test
    fun `web contents debugging is gated on a debug build`() {
        val source = SourceTree.kotlinSources().single { it.name == FACTORY_FILE }.code()

        // The call and the guard must be present together. Left ungated in a
        // release build, it exposes the WebView's contents to anything that can
        // reach the device's debug bridge.
        val enables = "setWebContentsDebuggingEnabled" in source
        assertTrue(
            "setWebContentsDebuggingEnabled must be guarded by BuildConfig.DEBUG " +
                "(BIT-33 R-11).",
            !enables || "BuildConfig.DEBUG" in source,
        )
    }
}
