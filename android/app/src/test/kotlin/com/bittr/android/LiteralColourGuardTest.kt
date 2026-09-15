package com.bittr.android

import com.bittr.android.SourceTree.codeWithoutLiterals
import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A colour value may be written in `Color.kt`, and nowhere else.
 *
 * `Color.kt` has said so since BIT-4 — *"Do not add a literal colour at a call site.
 * A colour that only exists inside a composable is a colour the designer cannot
 * change"* — and until BIT-156 that was the whole of the enforcement. The Value
 * screen's graph line was a hard-coded near-black for the entire life of the port.
 *
 * ### What the prose rule was actually protecting against
 *
 * Not untidiness. A value outside the theme has no dark counterpart, so it is
 * measured against one background and ships against two. That line was **10.97 : 1 on
 * the light canvas** — which is why nobody noticed, light mode looked right by
 * accident — and **2.43 : 1 on the dark one**, under the 3 : 1 floor WCAG 1.4.11 puts
 * on a graphical object. It is also invisible to `TokenContrastTest`, which measures
 * tokens: a value that is not a token is not in the table, so the guard that exists
 * to catch exactly this failure could not see it. BIT-95 lost the same way, with a
 * `switchAccent` that lived in `Canvas.kt` and shipped at 1.65 : 1.
 *
 * Both of those were found by a person looking at a render. This is the check that
 * does not need one.
 *
 * ### Scope
 *
 * The hex-literal form only — `Color(0x…)`, which is how both of the above were
 * written and the form the rule in `Color.kt` names. A call site can still bypass the
 * theme in other ways: `Color(red = …, green = …, blue = …)`, or `Color.Black` where a
 * token was meant. Those are the same mistake in a different shape and want their own
 * check; this one is written down as covering the shape that has occurred twice,
 * rather than implied to cover the idea.
 *
 * Comments and string literals are stripped before the scan ([codeWithoutLiterals]),
 * so this file and `Color.kt` may both keep explaining the rule in prose.
 */
class LiteralColourGuardTest {

    private companion object {

        /**
         * A `Color` built from a packed hex literal. Matches `Color(0xFF…)` and the
         * `androidx.compose.ui.graphics.Color(0x…)` a fully-qualified call site would
         * write, and not a `Color(…)` built from components or from another value.
         */
        val HEX_LITERAL = Regex("""\bColor\(\s*0[xX]""")

        /**
         * The one file allowed to hold colour values, matched by name because there
         * is exactly one of it and a path would break when the module moves.
         */
        const val PALETTE = "Color.kt"
    }

    @Test
    fun `colour values live in the palette and not at call sites`() {
        val offenders = SourceTree.kotlinSources(PALETTE)
            .filter { HEX_LITERAL.containsMatchIn(it.codeWithoutLiterals()) }
            .map { it.repoPath() }
            .sorted()

        assertEquals(
            "A colour is written outside $PALETTE. A value that is not a token has no " +
                "dark counterpart, so it is measured against one background and ships " +
                "against two, and `TokenContrastTest` cannot see it at all — it measures " +
                "tokens. That is how the Value screen's graph line shipped at 2.43 : 1 on " +
                "the dark canvas (BIT-156) and how `switchAccent` shipped at 1.65 : 1 " +
                "(BIT-95). Move it into $PALETTE, name it, and measure it there.",
            emptyList<String>(),
            offenders,
        )
    }

    /**
     * The scan finds the shape it is looking for where that shape is allowed.
     *
     * Without this, a regex that had drifted into matching nothing would report the
     * whole tree as compliant and pass — the same silent-green failure the guards in
     * this package exist to refuse, and the reason [SourceTree] will not return an
     * empty file list either.
     */
    @Test
    fun `the scan still recognises a colour value where one is allowed to be`() {
        val palette = SourceTree.kotlinSources().single { it.name == PALETTE }
        val found = HEX_LITERAL.findAll(palette.codeWithoutLiterals()).count()

        assertTrue(
            "Found no colour value in ${palette.repoPath()}, so this guard is looking " +
                "for a shape that no longer exists and would pass over a tree full of " +
                "them. Re-check $HEX_LITERAL against how the palette is written now.",
            found > 0,
        )
    }
}
