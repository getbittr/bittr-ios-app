package com.bittr.android

import com.bittr.android.SourceTree.code
import com.bittr.android.SourceTree.repoPath
import java.io.File
import java.util.regex.Pattern
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ties the OpenStreetMap credit to the basemap that requires it (BIT-119).
 *
 * [TileHostGuardTest] holds *who serves the tiles*. This holds *what the screen owes
 * the people who made them*, and the two are independent: a basemap served from
 * bittr's own storage is still built from OpenStreetMap data, and OSM's licence
 * requires the credit regardless of who serves it. `android/docs/tile-pipeline.md`
 * §3 states the requirement and the BIT-119 done-when list repeats it as "**in the
 * same commit as** the one that sets `STYLE_URI`".
 *
 * That phrase is the whole problem. It is a sequencing requirement, and a sequencing
 * requirement written only in an issue description is enforced by whoever happens to
 * be reading that description on the day. This file makes it a build failure instead.
 *
 * ### Why it is dormant today, and why that is the right shape
 *
 * `MapBasemap.STYLE_URI` is `null`, so the app draws no basemap and owes no basemap
 * credit — §3 is explicit that the string is deliberately *not* added ahead of that
 * commit, because it is the Growth & Content Lead's to word (BIT-56 is the
 * precedent) and because crediting OSM for a basemap the app does not draw would be
 * its own false statement. So the check below does nothing at all right now.
 *
 * A dormant check that has never fired is indistinguishable from a broken one, which
 * is what [the detectors fire on known violations] is for: it runs every detector
 * against a fixture that should trip it and a fixture that should not, so a
 * regression in the detector fails the build on the day it happens rather than on
 * the day it was needed. [TileHostGuardTest] carries the same self-test for the same
 * reason.
 *
 * ### Why nothing else would catch it
 *
 * - **The compiler will not.** The credit is a string rendered in a composable.
 *   Omitting it is not a type error; it is a screen that draws streets and says
 *   nothing about where they came from.
 * - **The other guards will not.** Every check in [TileHostGuardTest] passes on a
 *   build whose basemap is correctly hosted and entirely uncredited — the hostname
 *   is the only thing they read.
 * - **A review might not.** The commit that sets `STYLE_URI` is a one-constant diff,
 *   and that is exactly how it is described in the issue and in [MapBasemap]'s own
 *   KDoc. A one-line change reads as too small to have a licence obligation attached
 *   to it, and the moment it lands the map looks finished.
 *
 * ### What this cannot prove
 *
 * That the credit is *legible*. A scan can see that the constant exists and that the
 * map screen references it; it cannot see contrast, or ordering, or a credit pushed
 * under a fold. Those belong in a rendered assertion next to the map screen's other
 * Robolectric tests, and the failure messages below say so rather than implying this
 * file covers it.
 */
class BasemapAttributionGuardTest {

    private companion object {

        /**
         * The three files this guard reads, named rather than discovered.
         *
         * If one is renamed or split, [fileNamed] fails loudly — the alternative is
         * a scan that finds nothing, reports green, and covers nothing. That is the
         * same trade [TileHostGuardTest] makes for `MapBasemap.kt`.
         */
        const val BASEMAP_FILE = "MapBasemap.kt"
        const val COPY_FILE = "MapCopy.kt"
        const val SCREEN_FILE = "MapScreen.kt"

        /**
         * The `STYLE_URI` declaration, read as a literal.
         *
         * Deliberately a second copy of the pattern [TileHostGuardTest] uses, not a
         * shared helper: the two guards ask different questions of the same line and
         * should be able to fail independently. The duplication is safe because
         * neither treats "declaration not found" as a pass — reshape the declaration
         * and both go red in the same run, which is the loud outcome.
         */
        val STYLE_URI: Pattern =
            Pattern.compile("""STYLE_URI\s*:\s*String\?\s*=\s*(null|"([^"]*)")""")

        /**
         * The words the licence requires, and the only part of the sentence this
         * guard has an opinion about.
         *
         * The surrounding copy is the Growth & Content Lead's — whether it reads
         * "Map data © OpenStreetMap contributors" or something else is a copy
         * decision and not this file's business. The attribution itself is not a
         * copy decision, which is why the substring is pinned and nothing else is.
         *
         * Note this is a *different* string from the one already on the screen: the
         * approved alert says OSM is where the *places* are tagged, and that sentence
         * covers no map imagery. Matching on the full phrase rather than on
         * "OpenStreetMap" alone is what keeps the existing credit from satisfying a
         * requirement it does not meet.
         */
        const val REQUIRED_CREDIT = "OpenStreetMap contributors"

        /** `const val NAME` — group 1 is the name. */
        val CONST_DECL: Pattern = Pattern.compile("""const\s+val\s+([A-Z][A-Z0-9_]*)""")

        /**
         * A `STYLE_URI` value in the shape §2 settles on, for the self-test below.
         *
         * On a bittr host and carrying a real archive extension, so that this file
         * satisfies `TileHostGuardTest`'s own scans rather than needing to be added
         * to its allowlist — a guard that has to be excluded from a sibling guard is
         * a guard that weakened one to add another.
         */
        const val VERSIONED_ARCHIVE = "https://tiles.getbittr.com/basemap/2026-09/ch.pmtiles"

        /** The credit as it would actually be written, for the self-test below. */
        const val CREDIT_LINE =
            "const val OSM_CREDIT: String = \"Map data © " + REQUIRED_CREDIT + "\""

        /** Whichever way [styleUriLiteral] read the declaration. */
        sealed interface Result {
            object Null : Result

            data class Url(val value: String) : Result
        }

        /**
         * The `STYLE_URI` literal, or null when the declaration is not found —
         * which the caller treats as a failure, not as a pass.
         */
        fun styleUriLiteral(text: String): Result? {
            val matcher = STYLE_URI.matcher(text)
            if (!matcher.find()) return null
            val url = matcher.group(2)
            return if (url == null) Result.Null else Result.Url(url)
        }

        /**
         * The name of the constant in [COPY_FILE] carrying [REQUIRED_CREDIT], or
         * null when no constant does.
         *
         * Found by locating the credit text and walking back to the declaration that
         * encloses it, rather than by matching a whole declaration in one pattern:
         * the map's copy is written as multi-line concatenations of string literals
         * — `POWERED_BY_ALERT` runs to eight of them — and a pattern that tried to
         * span an initialiser would have to model that. The position of the credit
         * relative to the declarations around it does not need modelling.
         */
        fun creditConstant(text: String): String? {
            val at = text.indexOf(REQUIRED_CREDIT)
            if (at < 0) return null
            val matcher = CONST_DECL.matcher(text)
            var enclosing: String? = null
            while (matcher.find()) {
                if (matcher.start() > at) break
                enclosing = matcher.group(1)
            }
            return enclosing
        }

        /** Whether [SCREEN_FILE] reads the credit constant by name. */
        fun rendersCredit(text: String, constant: String): Boolean =
            "MapCopy.$constant" in text

        /**
         * The single file called [name] under the android tree.
         *
         * Fails rather than returns null, because every caller below would otherwise
         * have to decide what a missing anchor means, and there is only one right
         * answer.
         */
        fun fileNamed(name: String): File {
            val matches = SourceTree.runtimeConfigSources().filter { it.name == name }
            assertTrue(
                "Expected exactly one $name under the android tree; found ${matches.size}. " +
                    "This guard reads named files because a scan that finds nothing passes " +
                    "silently. If the map's sources moved, point it at their new home in the " +
                    "same commit.",
                matches.size == 1,
            )
            return matches.single()
        }
    }

    @Test
    fun `the OpenStreetMap credit ships with the basemap`() {
        val basemap = fileNamed(BASEMAP_FILE)
        val literal = styleUriLiteral(basemap.code())

        assertTrue(
            "Could not find the STYLE_URI declaration in ${basemap.repoPath()}. This guard " +
                "reads it to decide whether the app draws a basemap at all, so an unreadable " +
                "declaration means the credit requirement stops being checked. If the " +
                "declaration was reshaped, reshape this pattern and TileHostGuardTest's with " +
                "it.",
            literal != null,
        )

        // Null means the background-only style: no basemap is drawn, so no basemap
        // credit is owed, and adding one early would credit OSM for imagery the app
        // does not fetch. tile-pipeline.md §3 is explicit that this is deliberate.
        if (literal !is Result.Url) return

        val copy = fileNamed(COPY_FILE)
        val constant = creditConstant(copy.code())

        assertTrue(
            "MapBasemap.STYLE_URI is set to '${literal.value}', so this app now draws a " +
                "basemap built from OpenStreetMap data — but no constant in " +
                "${copy.repoPath()} carries the credit \"$REQUIRED_CREDIT\".\n" +
                "That credit is required by the data licence whoever serves the tiles, which " +
                "is why it is not satisfied by the existing BTCMap wording: that sentence " +
                "credits OSM for where the *places* are tagged and covers no map imagery.\n" +
                "This is done-when item 4 on BIT-119, and it is required in the same commit " +
                "as the STYLE_URI change rather than in a follow-up. The wording around the " +
                "credit is the Growth & Content Lead's to write (BIT-56 is the precedent); " +
                "the credit itself is the licence's and is not a copy decision.\n" +
                "Read android/docs/tile-pipeline.md §3.",
            constant != null,
        )
        requireNotNull(constant)

        val screen = fileNamed(SCREEN_FILE)

        assertTrue(
            "MapCopy.$constant carries the OpenStreetMap credit, but ${screen.repoPath()} " +
                "never reads it — so the string exists and the screen does not show it, " +
                "which is the same outcome as not having written it.\n" +
                "Render it on the map surface, next to where MapCopy.POWERED_BY is rendered " +
                "today.\n" +
                "Note what this guard still cannot see: that the credit is legible once " +
                "rendered. It reads a reference, not a pixel. Prove visibility with an " +
                "assertion in the map module's Robolectric tests, where the rest of this " +
                "screen is already checked without an emulator.",
            rendersCredit(screen.code(), constant),
        )
    }

    @Test
    fun `the detectors fire on known violations`() {
        assertEquals(
            "The STYLE_URI reader no longer recognises the null declaration it has to read " +
                "today. It would report 'no basemap' forever and the credit check would " +
                "never arm.",
            Result.Null,
            styleUriLiteral("""    val STYLE_URI: String? = null"""),
        )

        assertEquals(
            "The STYLE_URI reader no longer recognises a set declaration, which is the only " +
                "state that owes a credit.",
            Result.Url(VERSIONED_ARCHIVE),
            styleUriLiteral("""val STYLE_URI: String? = "$VERSIONED_ARCHIVE""""),
        )

        assertEquals(
            "The credit detector no longer finds a credit that is present, so the guard " +
                "would fail a commit that did everything right — and the fix for a guard " +
                "that cries wolf is that someone deletes it.",
            "OSM_CREDIT",
            creditConstant(CREDIT_LINE),
        )

        assertEquals(
            "The credit detector attributes the credit to the wrong constant when several " +
                "are declared, so the render check below it would look for a name that is " +
                "not the one holding the string.",
            "OSM_CREDIT",
            creditConstant(
                """
                const val TITLE: String = "Pay with bitcoin"
                $CREDIT_LINE
                const val CLOSE: String = "Close"
                """.trimIndent(),
            ),
        )

        assertEquals(
            "The credit detector accepts the *places* credit as a basemap credit. That " +
                "sentence is already in the app, so the guard would pass the moment it armed " +
                "and would never have asked for anything.",
            null,
            creditConstant(
                """const val POWERED_BY_ALERT: String = "uses OpenStreetMap to tag places"""",
            ),
        )

        assertEquals(
            "The credit detector reports a credit in a file that has none, which would let " +
                "an absent credit satisfy the check.",
            null,
            creditConstant("""const val TITLE: String = "Pay with bitcoin""""),
        )

        assertTrue(
            "The render detector no longer sees the credit constant being read, so a " +
                "correctly rendered credit would fail the guard.",
            rendersCredit("""Text(text = MapCopy.OSM_CREDIT, style = small)""", "OSM_CREDIT"),
        )

        assertTrue(
            "The render detector reports a constant the screen never reads. A string " +
                "declared and never shown would pass — which is the exact failure this " +
                "guard exists to catch, one step further along.",
            !rendersCredit("""Text(text = MapCopy.POWERED_BY, style = small)""", "OSM_CREDIT"),
        )
    }
}
