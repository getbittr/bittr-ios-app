package com.bittr.android

import com.bittr.android.SourceTree.code
import com.bittr.android.SourceTree.codeWithoutLiterals
import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The navigation policy is told which **frame** each navigation is for, and the
 * telling cannot be quietly undone (BIT-58).
 *
 * ### The rule this encodes
 *
 * > An origin gate reasons about *the page*; a JS bridge is exposed per *frame*.
 *
 * `shouldOverrideUrlLoading` fires for subframe navigations, and `view.url` is
 * the **main frame's** URL. Gate on the second while handling the first and a
 * cross-origin `<iframe>` on a `getbittr.com` page is judged as first-party —
 * which is the residual gap in the iOS fix (`decidePolicyFor` reading
 * `webView.url`) that this port is not repeating.
 *
 * ### Why a source scan rather than a behavioural test
 *
 * The behaviour is covered: `WebsiteNavigationPolicyTest` asserts the demotion,
 * and `CrossOriginIframeIsolationTest` drives a real cross-origin iframe against
 * a real WebView. What neither can catch is the *shape* regression — someone
 * giving `isForMainFrame` a default value, or passing a literal `true` at the
 * `shouldOverrideUrlLoading` call site "to keep it compiling". Both would leave
 * every existing test green while removing the check entirely, because in v1 no
 * outcome varies by trust. That is exactly the class of change a guard test is
 * for.
 */
class WebViewFrameScopeGuardTest {

    private companion object {
        const val POLICY_FILE = "WebsiteNavigationPolicy.kt"
        const val WEBVIEW_FILE = "HardenedWebView.kt"

        /** The platform accessor that answers "which frame is this for?". */
        const val FRAME_ACCESSOR = "request.isForMainFrame"
    }

    /**
     * Comments stripped. Both files below explain the frame/page distinction at
     * length and quote the very shapes this guard forbids — a KDoc line reading
     * `isForMainFrame = true` as an example of what not to write would otherwise
     * fail the check it is illustrating.
     */
    private fun source(name: String): String =
        SourceTree.kotlinSources().single { it.name == name }.code()

    @Test
    fun `the navigation policy takes the frame as a required parameter`() {
        val policy = source(POLICY_FILE)

        assertTrue(
            "$POLICY_FILE must declare an `isForMainFrame` parameter on decide(). " +
                "Without it the policy cannot distinguish a top-level navigation from " +
                "one made by a cross-origin iframe, and a subframe silently inherits " +
                "the main frame's trust (BIT-58).",
            "isForMainFrame" in policy,
        )

        // A default is how the check gets opted out of without deleting it: every
        // existing call site keeps compiling and the new one forgets to pass it.
        // Requiring the argument is what turned up the second call site in
        // WebsiteScreen.kt when this was introduced.
        val defaulted = Regex("""isForMainFrame\s*:\s*Boolean\s*=""").containsMatchIn(policy)

        assertTrue(
            "`isForMainFrame` must not have a default value in $POLICY_FILE. A default " +
                "means a caller that forgets the frame compiles anyway — and a caller " +
                "that forgets the frame is precisely the bug the parameter exists to " +
                "prevent.",
            !defaulted,
        )
    }

    @Test
    fun `the WebView passes the request's real frame, not a constant`() {
        val webView = source(WEBVIEW_FILE)

        assertTrue(
            "$WEBVIEW_FILE must pass $FRAME_ACCESSOR into WebsiteNavigationPolicy.decide(). " +
                "WebResourceRequest is the only thing that knows whether a navigation " +
                "came from the main frame; view.url is the main frame's URL regardless " +
                "of which frame asked (BIT-58).",
            FRAME_ACCESSOR in webView,
        )

        // `isForMainFrame = true` inside shouldOverrideUrlLoading would compile, read
        // as harmless, and assert that every subframe navigation is a top-level one.
        val hardcoded = Regex("""isForMainFrame\s*=\s*(true|false)\b""")
            .containsMatchIn(webView)

        assertTrue(
            "$WEBVIEW_FILE must not pass a literal for isForMainFrame. The value has to " +
                "come from the WebResourceRequest; a constant is the check written down " +
                "and then switched off.",
            !hardcoded,
        )
    }

    @Test
    fun `no other file decides a navigation without naming a frame`() {
        // decide() is the single chokepoint for "may this navigation proceed", so
        // every call to it must state a frame. Kotlin enforces that the argument is
        // present; this checks that a caller outside the two reviewed files has not
        // appeared, since a new call site is a new place for the frame to be got
        // wrong.
        val allowed = setOf(
            WEBVIEW_FILE,
            "WebsiteScreen.kt",
            POLICY_FILE,
            "WebsiteNavigationPolicyTest.kt",
            "WebViewFrameScopeGuardTest.kt",
        )

        val offenders = SourceTree.kotlinSources()
            .filterNot { it.name in allowed }
            .filter { "WebsiteNavigationPolicy.decide" in it.codeWithoutLiterals() }
            .map { it.repoPath() }

        assertTrue(
            "WebsiteNavigationPolicy.decide() is called from an unreviewed file. Each " +
                "call site has to decide what frame it is speaking for, and getting that " +
                "wrong is not visible at the call site — so a new one is a review, not a " +
                "refactor.\nOffending files:\n  " + offenders.joinToString("\n  "),
            offenders.isEmpty(),
        )
    }
}
