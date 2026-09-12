package com.bittr.android

import java.io.File
import org.junit.Assert.assertTrue

/**
 * Read-only view of the Kotlin sources in the `android/` tree, for the guard tests
 * that enforce rules the compiler cannot.
 *
 * Gradle runs unit tests with the working directory set to the module directory
 * (`android/app`), so the Gradle root is one level up. [root] verifies that rather
 * than assuming it: a source-scan test that walks an empty tree passes silently,
 * which is the one failure mode that would make these guards worse than useless.
 */
internal object SourceTree {

    val root: File by lazy {
        val candidate = File("..").canonicalFile
        assertTrue(
            "Expected the Gradle root at $candidate (working dir ${File(".").canonicalFile}), " +
                "but it has no settings.gradle.kts. The guard tests scan the source tree " +
                "from there; if the working directory has moved they would scan nothing " +
                "and pass without checking anything.",
            File(candidate, "settings.gradle.kts").isFile,
        )
        candidate
    }

    /** Every non-generated Kotlin source file under `android/`, excluding [excludeFileNames]. */
    fun kotlinSources(vararg excludeFileNames: String): List<File> {
        val excluded = excludeFileNames.toSet()
        val files = root.walkTopDown()
            .onEnter { it.name != "build" && it.name != ".gradle" }
            .filter { it.isFile && it.extension == "kt" }
            .filterNot { it.name in excluded }
            .toList()
        assertTrue(
            "Found no Kotlin sources under $root — the scan is not looking where it thinks.",
            files.isNotEmpty(),
        )
        return files
    }

    fun File.repoPath(): String = relativeTo(root).path

    /**
     * This file's source with **comments removed** and string literals kept.
     *
     * Use this when the question is "what value does the code hold" — the
     * allowlist literal check in `WebViewBridgeOriginGuardTest` is the case.
     */
    fun File.code(): String = stripKotlin(readText(), keepStringLiterals = true)

    /**
     * This file's source with **comments and string literals removed**.
     *
     * Use this when the question is "does the code *call* this API".
     *
     * ### Why the guards cannot scan raw text
     *
     * Every guard in this package started as a substring search over
     * `readText()`, and each one went red the moment the code it guards was
     * written — not because a banned call appeared, but because a file
     * *explained* the ban. `HardenedWebView.kt` documents why
     * `addJavascriptInterface` is not used; `FirstPartyOrigins.kt` documents that
     * `allowedOriginRules` is never `"*"`; `CrossOriginIframeIsolationTest.kt`
     * spends a paragraph on the iOS gap it exists to prevent. A guard that treats
     * those as violations has exactly one stable outcome: the next person deletes
     * the sentence, or adds the file to an allowlist, and the guard ends up
     * protecting less than it did before.
     *
     * So the scan reads code. Prose may name a banned API — that is how the ban
     * stays understood — and code may not.
     *
     * String literals go too, because an assertion message naming the API is
     * prose that happens to be quoted (`JavascriptInterfaceGuardTest` names
     * `addWebMessageListener` in the failure it prints). The cost is that a
     * reflective `getMethod("addJavascriptInterface")` is invisible here; the CI
     * grep over non-Kotlin sources does not cover that either, so it is written
     * down as a known edge rather than implied to be handled.
     */
    fun File.codeWithoutLiterals(): String = stripKotlin(readText(), keepStringLiterals = false)

    /**
     * [File.readText] with comments removed, as a free function taking the file.
     *
     * The same thing [File.code] is, in the call shape `:core:wallet-ldk`'s
     * `WalletSourceTree` uses — kept so a guard moving between the two modules
     * does not have to change its call sites. It goes through [stripKotlin]
     * rather than through a crude comment strip, so a `//` inside a string
     * literal stays part of the string.
     */
    fun codeOf(file: File): String = file.code()

    /**
     * Removes Kotlin comments — and, when [keepStringLiterals] is false, string
     * and character literals — from [text].
     *
     * Written as one left-to-right pass rather than as regexes because the two
     * constructs nest in each other and a regex cannot tell which one it is
     * inside: `"https://getbittr.com"` contains a `//` that does not start a
     * comment, and a KDoc block can contain an unbalanced quote. Literals are
     * therefore recognised *before* comments at every position, which is the
     * whole of the rule.
     *
     * Removed text is dropped, not blanked, so line numbers are not preserved.
     * No guard reports one, and the file path plus the symbol is what makes a
     * failure actionable.
     */
    fun stripKotlin(text: String, keepStringLiterals: Boolean): String {
        val out = StringBuilder(text.length)
        var i = 0

        fun keep(from: Int, to: Int) {
            if (keepStringLiterals) out.append(text, from, to)
        }

        while (i < text.length) {
            when {
                // Raw strings first: `"""` also starts with `"`, and the HTML and
                // JavaScript fixtures in the instrumented tests live in them.
                text.startsWith("\"\"\"", i) -> {
                    val end = text.indexOf("\"\"\"", i + 3)
                    val stop = if (end < 0) text.length else end + 3
                    keep(i, stop)
                    i = stop
                }

                text[i] == '"' || text[i] == '\'' -> {
                    val quote = text[i]
                    var j = i + 1
                    while (j < text.length && text[j] != quote) {
                        // A backslash consumes the next character, so `"\""` ends
                        // where it should rather than two characters early.
                        if (text[j] == '\\') j++
                        j++
                    }
                    val stop = minOf(j + 1, text.length)
                    keep(i, stop)
                    i = stop
                }

                text.startsWith("//", i) -> {
                    val newline = text.indexOf('\n', i)
                    // The newline itself is kept: dropping it would join the
                    // commented line to the next one and could fuse two tokens.
                    i = if (newline < 0) text.length else newline
                }

                text.startsWith("/*", i) -> {
                    // Kotlin block comments nest, unlike Java's.
                    var depth = 1
                    var j = i + 2
                    while (j < text.length && depth > 0) {
                        when {
                            text.startsWith("/*", j) -> { depth++; j += 2 }
                            text.startsWith("*/", j) -> { depth--; j += 2 }
                            else -> j++
                        }
                    }
                    i = j
                }

                else -> {
                    out.append(text[i])
                    i++
                }
            }
        }
        return out.toString()
    }
}
