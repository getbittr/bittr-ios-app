package com.bittr.android

import com.bittr.android.SourceTree.codeWithoutLiterals
import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `addJavascriptInterface` appears nowhere in the app (BIT-33 R-1).
 *
 * ### Why this is a test and not a code review note
 *
 * R-1 says "enforce with a lint rule or CI grep, not a convention", and the
 * reason is that the banned call is the *obvious* translation of what iOS does.
 * `WebsiteViewController` installs a `WKScriptMessageHandler` and posts LNURLs to
 * it from injected JavaScript; anyone porting that screen who reaches for the
 * Android equivalent lands on `addJavascriptInterface` within a minute, because
 * that is what every tutorial and every model completion offers. It is also the
 * one bridge API with **no origin scoping at all** — the object it exposes is
 * visible to whatever the WebView happens to have loaded, and one of the five
 * call sites loads an arbitrary URL from BTCMap place data.
 *
 * So the ban is checked mechanically, twice: here (running in CI's `Unit tests`
 * step, so it fails in about a minute) and again as a grep over the non-Kotlin
 * sources in the workflow — Java, XML and the manifests, which this scan does not
 * read at all.
 *
 * ### The scan reads code, not prose
 *
 * Comments and string literals are stripped before the search
 * ([SourceTree.codeWithoutLiterals]), so this file is not the only one allowed to
 * *explain* the ban — `HardenedWebView.kt` and the instrumented tests all do, and
 * they have to, because the reason the API is banned is the whole point. What no
 * file may do is call it.
 *
 * That split is also why the workflow's grep is scoped to non-Kotlin files rather
 * than the whole tree: a raw grep over `android/` fails on its own documentation,
 * and a check that cries wolf gets deleted.
 *
 * ### If a bridge is ever genuinely needed
 *
 * The answer is not to add a name to an allowlist here. It is
 * `WebViewCompat.addWebMessageListener` with `allowedOriginRules` pinned to
 * `FirstPartyOrigins.allowedOriginRules` (R-3) — a different API with an origin
 * argument that cannot be omitted. `WebViewBridgeOriginGuardTest` covers that
 * one. There is deliberately no escape hatch in this test.
 */
class JavascriptInterfaceGuardTest {

    private companion object {
        /**
         * Also catches `@JavascriptInterface`, the annotation a bridge object's
         * methods need in order to be callable — so a diff that adds the object
         * before wiring it up still fails here rather than looking clean.
         */
        val BANNED_SYMBOLS = listOf("addJavascriptInterface", "JavascriptInterface")

        /**
         * This file holds the banned names as live string constants, so it is the
         * one file that fails its own check. Every other file is free to name the
         * API in a comment and forbidden to call it — see the class comment.
         */
        val ALLOWED_FILES = setOf("JavascriptInterfaceGuardTest.kt")
    }

    @Test
    fun `addJavascriptInterface appears nowhere in the app`() {
        val offenders = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .mapNotNull { file ->
                val code = file.codeWithoutLiterals()
                val hit = BANNED_SYMBOLS.firstOrNull { it in code } ?: return@mapNotNull null
                "${file.repoPath()} (calls $hit)"
            }

        assertTrue(
            "addJavascriptInterface must not appear anywhere in the app (BIT-33 R-1).\n" +
                "It is the one WebView bridge API with no origin scoping: the object it " +
                "exposes is reachable by whatever page the WebView has loaded, and S-36 " +
                "loads an arbitrary third-party URL from BTCMap place data. A bridge there " +
                "would let any merchant page the user opens from the map drive a Lightning " +
                "flow.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "There is no allowlist for this one. If a first-party page genuinely needs " +
                "to hand the wallet an LNURL, use WebViewCompat.addWebMessageListener with " +
                "allowedOriginRules = FirstPartyOrigins.allowedOriginRules (R-3) and read " +
                "WebViewBridgeOriginGuardTest first.",
            offenders.isEmpty(),
        )
    }
}
