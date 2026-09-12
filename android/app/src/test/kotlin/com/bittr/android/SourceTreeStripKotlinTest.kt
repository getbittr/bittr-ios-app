package com.bittr.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The scanner the WebView guards are built on (BIT-33 R-1/R-3, BIT-58).
 *
 * ### Why this is worth its own test
 *
 * `SourceTree.stripKotlin` is the thing standing between "no file calls
 * `addJavascriptInterface`" and "no file *mentions* it". Every guard in this
 * package is only as good as it, and it fails in a direction nobody notices: a
 * stripper that is too aggressive deletes the code the guard was going to read,
 * and the guard then passes because it found nothing. A green tick is the output
 * of both "the app is clean" and "the scan removed the evidence", so the
 * stripper gets checked directly.
 *
 * The cases below are the ones the real sources actually contain — a `//` inside
 * a URL, a KDoc paragraph naming a banned API, a raw string full of HTML — not
 * an inventory of Kotlin's grammar.
 */
class SourceTreeStripKotlinTest {

    private fun code(text: String) = SourceTree.stripKotlin(text, keepStringLiterals = true)

    private fun bare(text: String) = SourceTree.stripKotlin(text, keepStringLiterals = false)

    @Test
    fun `a slash-slash inside a string is not a comment`() {
        // This is the case that makes the pass order load-bearing:
        // FirstPartyOrigins.kt builds its origin rules as "https://$host".
        val source = """val origin = "https://getbittr.com" ; val port = 443"""

        assertEquals(
            "Everything after the // in the URL was eaten, so a scan of this file " +
                "would not see `val port` at all — and a guard reading it would pass " +
                "by finding nothing.",
            source,
            code(source),
        )
    }

    @Test
    fun `a line comment goes and the line after it stays`() {
        val source = "val a = 1 // addJavascriptInterface explained here\nval b = 2"

        val stripped = code(source)

        assertFalse(
            "The comment survived the strip, so prose naming a banned API still " +
                "reads as a call.",
            "addJavascriptInterface" in stripped,
        )
        assertTrue("`val a = 1` was dropped with its trailing comment.", "val a = 1" in stripped)
        assertTrue("`val b = 2` was dropped with the comment above it.", "val b = 2" in stripped)
    }

    @Test
    fun `a KDoc block goes, including a nested block comment`() {
        val source = """
            /**
             * Never call addJavascriptInterface. /* not even in a nested aside */
             */
            fun create() = Unit
        """.trimIndent()

        val stripped = code(source)

        assertFalse(
            "Kotlin block comments nest — a stripper that stops at the first `*/` " +
                "leaves the tail of the comment behind and finds the banned name in it.",
            "addJavascriptInterface" in stripped,
        )
        assertTrue("The declaration below the KDoc was removed with it.", "fun create()" in stripped)
    }

    @Test
    fun `an unterminated block comment does not swallow the rest silently`() {
        // It does swallow it — there is nothing else it could do — but the file
        // would not compile either, so this pins the behaviour rather than
        // leaving it to be discovered during an incident.
        val stripped = code("fun a() = Unit\n/* opened and never closed\nfun b() = Unit")

        assertTrue("The code before the comment must survive.", "fun a()" in stripped)
        assertFalse("Everything after an unterminated comment is comment.", "fun b()" in stripped)
    }

    @Test
    fun `raw strings are kept whole when literals are kept`() {
        // The instrumented tests hold HTML and JavaScript fixtures in raw
        // strings, and those contain both quotes and `//`.
        val source = "val page = \"\"\"<script src=\"//evil.example/x.js\"></script>\"\"\"\nval n = 1"

        val stripped = code(source)

        assertTrue("The raw string was truncated.", "evil.example" in stripped)
        assertTrue("Code after the raw string was lost.", "val n = 1" in stripped)
    }

    @Test
    fun `string literals go when they are asked to go`() {
        // JavascriptInterfaceGuardTest names the permitted API inside the message
        // it prints on failure. That is prose that happens to be quoted.
        val source = """val message = "use addWebMessageListener instead" ; val n = 1"""

        val stripped = bare(source)

        assertFalse(
            "A quoted API name still reads as a call, so the guard flags the file " +
                "that documents the rule.",
            "addWebMessageListener" in stripped,
        )
        assertTrue("The surrounding code must remain readable to the scan.", "val n = 1" in stripped)
    }

    @Test
    fun `an escaped quote does not end a string early`() {
        // `"\""` ends two characters later than a naive scan thinks, and the
        // scan then treats the following code as string contents.
        val source = """val quote = "a\"b" ; val addJavascriptInterface = 1"""

        val stripped = bare(source)

        assertTrue(
            "The scan lost its place inside the escaped quote and swallowed the " +
                "declaration after it — which is a banned call going unseen.",
            "val addJavascriptInterface = 1" in stripped,
        )
    }

    @Test
    fun `a char literal holding a quote does not end a string early`() {
        val source = """val q = '"' ; val n = 1"""

        assertTrue(
            "A char literal containing a quote was treated as the start of a " +
                "string, so the rest of the line vanished.",
            "val n = 1" in bare(source),
        )
    }

    @Test
    fun `the real hardened WebView still reads as code after stripping`() {
        // The end-to-end check: strip the actual factory and confirm the
        // constructor call the guards look for is still there. If a future edit
        // to the stripper starts eating real code, this is the test that says so
        // rather than three guards quietly passing.
        val factory = SourceTree.kotlinSources()
            .single { it.name == "HardenedWebView.kt" }
            .let { SourceTree.stripKotlin(it.readText(), keepStringLiterals = false) }

        assertTrue(
            "The WebView constructor call disappeared from HardenedWebView.kt when " +
                "stripped. Every WebView guard reads this text; if the construction " +
                "is invisible here, it is invisible everywhere.",
            Regex("""(?<![A-Za-z0-9_.])WebView\s*\(""").containsMatchIn(factory),
        )
        assertFalse(
            "HardenedWebView.kt's prose about addJavascriptInterface survived the " +
                "strip, so the guard will keep flagging the file that explains the ban.",
            "addJavascriptInterface" in factory,
        )
    }
}
