package com.bittr.android

import com.bittr.android.SourceTree.code
import com.bittr.android.SourceTree.codeWithoutLiterals
import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * If a WebView message bridge is ever added, its origin allowlist is exact
 * (BIT-33 R-3) — and in particular it never contains the block explorer.
 *
 * ### The correction this test encodes
 *
 * BIT-21 asked for `allowedOriginRules` "pinned to the first-party hosts" and its
 * call-site table listed the block explorer among them. It is not first-party:
 * `EnvironmentConfig.explorerURL` is `https://mempool.space` in Release and
 * `https://esplora-regtest.bittr.io` in Debug. Implemented as worded, the bridge
 * would have been handed to an origin nobody here controls — a mistake that
 * reads as correct in review, because "the explorer" sounds like ours.
 *
 * That is the kind of error a test catches and a code review does not, so the
 * host names are written down here rather than described.
 *
 * ### No bridge ships in v1
 *
 * So most of this test is currently asserting a property of an allowlist nothing
 * reads. That is on purpose. The allowlist is the artefact a future bridge must
 * use, and the moment it is added is the moment nobody wants to be re-deriving
 * which hosts belong in it.
 */
class WebViewBridgeOriginGuardTest {

    private companion object {
        /** The only bridge API this app is permitted to use, if it uses one at all. */
        const val BRIDGE_API = "addWebMessageListener"

        /** The file allowed to define the allowlist. */
        const val ALLOWLIST_FILE = "FirstPartyOrigins.kt"

        /**
         * Hosts that must never appear in the allowlist.
         *
         * The explorer hosts are third-party (see the class comment). `*` is the
         * wildcard `allowedOriginRules` accepts and which turns the origin
         * argument into decoration.
         */
        val FORBIDDEN_IN_ALLOWLIST = listOf(
            "mempool.space",
            "esplora-regtest.bittr.io",
        )

        val ALLOWED_FILES = setOf(
            ALLOWLIST_FILE,
            "WebViewBridgeOriginGuardTest.kt",
        )
    }

    @Test
    fun `the first-party allowlist is exactly getbittr_com`() {
        // Read rather than imported: :app depends on :feature:website, so this
        // could call FirstPartyOrigins.allowedOriginRules directly — but then the
        // assertion would be "the code equals itself" for any value the code
        // happens to hold. The literal is written out here so that changing the
        // allowlist requires changing this test, which is the review moment.
        // Comments stripped, so a commented-out older allowlist above the live one
        // cannot be the declaration this regex finds.
        val source = SourceTree.kotlinSources()
            .single { it.name == ALLOWLIST_FILE }
            .code()

        val allowed = Regex("""private val ALLOWED = setOf\(([^)]*)\)""")
            .find(source)
            ?.groupValues
            ?.get(1)
            ?.split(',')
            ?.map { it.trim().trim('"') }
            ?.filter { it.isNotEmpty() }
            ?: error(
                "Could not find `private val ALLOWED = setOf(…)` in $ALLOWLIST_FILE. " +
                    "This guard reads that declaration; if it has been renamed or " +
                    "restructured, update the pattern here — do not delete the check.",
            )

        assertEquals(
            "The first-party origin allowlist must be exactly getbittr.com (BIT-33 R-3).\n" +
                "The block explorer is NOT first-party — EnvironmentConfig.explorerURL is " +
                "https://mempool.space in Release — and neither is a map place's website. " +
                "Adding a host here grants it whatever bridge capability the app has, so " +
                "it is a security review, not a config change.",
            listOf("getbittr.com"),
            allowed,
        )
    }

    @Test
    fun `no wildcard or third-party host reaches the origin allowlist`() {
        // Comments stripped first, then literals read out of what is left. The
        // file's prose explains why the explorer is excluded and why the rules are
        // never `*`, and necessarily quotes both — so scanning the raw text finds
        // the documentation and calls it a violation.
        val source = SourceTree.kotlinSources().single { it.name == ALLOWLIST_FILE }.code()

        val literals = Regex("\"([^\"]*)\"").findAll(source).map { it.groupValues[1] }.toList()

        val offenders = literals.filter { literal ->
            literal == "*" || FORBIDDEN_IN_ALLOWLIST.any { it in literal }
        }

        assertTrue(
            "$ALLOWLIST_FILE must not contain a wildcard origin or a third-party host as a " +
                "string literal (BIT-33 R-3). allowedOriginRules = \"*\" makes the origin " +
                "argument decoration, and the explorer hosts are third-party.\n" +
                "Offending literals: $offenders",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the bridge API is only ever called from the allowlist's own file`() {
        val offenders = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .filter { BRIDGE_API in it.codeWithoutLiterals() }
            .map { it.repoPath() }

        assertTrue(
            "WebViewCompat.$BRIDGE_API may only be called from $ALLOWLIST_FILE, so that the " +
                "call and its allowedOriginRules argument are in the file this test reads " +
                "(BIT-33 R-3). A call elsewhere can pass any origin rules it likes.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "Note that no bridge ships in v1 and androidx.webkit is not a dependency of " +
                ":feature:website, so adding this call means adding that dependency first — " +
                "which is the visible line in the diff where the review belongs.",
            offenders.isEmpty(),
        )
    }
}
