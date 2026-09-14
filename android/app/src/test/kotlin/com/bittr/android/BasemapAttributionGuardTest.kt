package com.bittr.android

import com.bittr.android.SourceTree.code
import com.bittr.android.SourceTree.repoPath
import java.io.File
import java.util.regex.Pattern
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ties the basemap's credits to the basemap that requires them (BIT-119).
 *
 * [TileHostGuardTest] holds *who serves the tiles*. This holds *what the screen owes
 * the people who made them*, and the two are independent: a basemap served from
 * bittr's own storage is still built from someone else's work, and their licences
 * require the credits regardless of who serves it. `android/docs/tile-pipeline.md`
 * §3 states the requirement and the BIT-119 done-when list repeats it as "**in the
 * same commit as** the one that sets `STYLE_URI`".
 *
 * There are **two** credits, not one — see [REQUIRED_CREDITS]. The data is
 * OpenStreetMap's; the tiles are built with the OpenMapTiles schema, which is CC-BY
 * and asks for its own. This file originally pinned only the first, which meant it
 * reported success on a half-met obligation. BIT-149 caught that, and the
 * [OSM_ONLY_CREDIT_LINE] fixture now holds the door shut.
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
         * The OSM half of what the licences require — one of the two phrases in
         * [REQUIRED_CREDITS], and part of the only thing this guard has an opinion
         * about.
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
         *
         * The `©` is U+00A9 and is part of what is pinned, per BIT-140. `(c)` and
         * `&copy;` are not accepted: the second renders literally in a Compose
         * `Text`, so accepting it would pass a build that shows the entity to a user.
         */
        const val OSM_CREDIT = "© OpenStreetMap contributors"

        /**
         * The other half, which this guard did not ask for until BIT-149.
         *
         * The tiles are built by planetiler's **OpenMapTiles** profile, and that
         * schema is CC-BY: the credit it requires is `© OpenMapTiles` *alongside*
         * the OSM one, not instead of it. Two upstreams, two obligations, and only
         * one of them was written down here.
         *
         * This is worth stating plainly because of the shape of the failure it fixes:
         * before this constant existed, the guard passed in exactly the state the
         * licence was not met in. A credit reading "Map data © OpenStreetMap
         * contributors" — the wording BIT-140 approved, and the obvious thing to
         * write — satisfied every check in this file while leaving the CC-BY grant
         * unmet. A guard that is green on the violation it was written to prevent is
         * worse than no guard, because it is also an assurance.
         *
         * Not taken from documentation. The built archive's own PMTiles metadata
         * carries `attribution` with both credits as HTML links, written by
         * planetiler rather than by anything in `android/tools/tile-pipeline/` — so
         * the requirement is visible in the artefact the app will actually serve.
         * That is also why only the two `©` phrases are pinned and the links are not:
         * the metadata's form is the tile builder's, and the on-screen sentence is
         * the Growth & Content Lead's.
         *
         * ### Why the `.org` is part of the pin
         *
         * This constant read `© OpenMapTiles` when BIT-149 first landed, copied from
         * the archive metadata and from planetiler's banner. Both render it **as a
         * link**, and that turns out to be the whole of it. `NOTICE.md` in the same
         * pinned jar states the obligation as two alternatives, not one:
         *
         * > Products or services using maps derived from OpenMapTiles schema need to
         * > visibly credit "OpenMapTiles.org" or reference "OpenMapTiles" with a link
         * > to openmaptiles.org
         *
         * BIT-140 fixed this credit as a plain Compose `Text`, outside the existing
         * line's `clickable` and not itself clickable. There is no link, so the
         * second alternative is unavailable and the first is the one that has to be
         * met — and the first names `OpenMapTiles.org`, with the suffix. A bare
         * `© OpenMapTiles` in an unclickable `Text` satisfies neither alternative,
         * which would have been the same failure BIT-149 exists to fix, one level
         * down: a guard green on a credit that does not discharge the licence.
         *
         * So the `.org` is load-bearing rather than decorative, and the bare form is
         * rejected below. If a later change makes this credit a real link, the second
         * alternative opens up and this pin should be relaxed **in that commit**, not
         * loosened to clear a red build.
         */
        const val OMT_CREDIT = "© OpenMapTiles.org"

        /**
         * Every phrase the two upstream licences require on the map surface.
         *
         * Checked independently rather than as one fixed sentence: the order, the
         * separator and the surrounding words are copy, and pinning the whole line
         * would make this file the arbiter of a sentence it has no business writing.
         * Whether they live in one constant or two is likewise not pinned — only that
         * each is present and each is rendered.
         */
        val REQUIRED_CREDITS = listOf(OMT_CREDIT, OSM_CREDIT)

        /** `const val NAME` — group 1 is the name. */
        val CONST_DECL: Pattern = Pattern.compile("""const\s+val\s+([A-Z][A-Z0-9_]*)""")

        /**
         * A `STYLE_URI` value in the shape §2 settles on, for the self-test below.
         *
         * The **style document**, not the archive beside it. That distinction was
         * corrected on BIT-139 after this fixture first landed pointing at
         * `ch.pmtiles`: the archive is referenced by the style's source as a
         * `pmtiles://` URL, and `STYLE_URI` is what MapLibre is handed. A fixture
         * that models the wrong shape teaches the wrong shape to whoever reads it
         * next, which for a one-constant change is the whole of the guidance.
         *
         * On a bittr host and carrying a tile-shaped marker, so that this file
         * satisfies `TileHostGuardTest`'s own scans rather than needing to be added
         * to its allowlist — a guard that has to be excluded from a sibling guard is
         * a guard that weakened one to add another.
         */
        const val VERSIONED_STYLE = "https://tiles.getbittr.com/basemap/2026-09/style.json"

        /**
         * A complete credit line, for the self-test below.
         *
         * Built from [REQUIRED_CREDITS] rather than spelled out, so the fixture
         * cannot drift from the phrases the guard actually pins. The framing words
         * are invented here and are *not* a proposal — BIT-140 worded the OSM half
         * before the OpenMapTiles obligation was known, so the shipped sentence is
         * BIT-149's to settle, not this file's.
         */
        val CREDIT_LINE =
            "const val BASEMAP_ATTRIBUTION: String = " +
                "\"Map data ${REQUIRED_CREDITS.joinToString(" ")}\""

        /**
         * The credit as it stood before BIT-149: the OSM half alone.
         *
         * This is the fixture that matters most in this file. It is not a
         * hypothetical offender — it is the exact string BIT-140 approved and the
         * exact state this guard used to pass, so if the detector ever accepts it
         * again the regression is back in full.
         */
        val OSM_ONLY_CREDIT_LINE =
            "const val BASEMAP_ATTRIBUTION: String = \"Map data $OSM_CREDIT\""

        /**
         * The bare `© OpenMapTiles` this constant used to accept.
         *
         * A second "not hypothetical" fixture, for the same reason as
         * [OSM_ONLY_CREDIT_LINE]: it is the form both planetiler and the archive
         * metadata show, so it is what anyone writing this line from the upstream
         * sources would reach for. Unlinked, it meets neither alternative in the
         * CC-BY notice — see [OMT_CREDIT].
         */
        val BARE_OMT_CREDIT_LINE =
            "const val BASEMAP_ATTRIBUTION: String = " +
                "\"Map data $OSM_CREDIT, design © OpenMapTiles\""

        /** The same line with the two substitute forms the credits exclude. */
        const val ENTITY_CREDIT_LINE =
            "const val BASEMAP_ATTRIBUTION: String = " +
                "\"Map data &copy; OpenMapTiles &copy; OpenStreetMap contributors\""

        const val ASCII_CREDIT_LINE =
            "const val BASEMAP_ATTRIBUTION: String = " +
                "\"Map data (c) OpenMapTiles (c) OpenStreetMap contributors\""

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
         * The name of the constant in [COPY_FILE] carrying [credit], or null when no
         * constant does.
         *
         * Found by locating the credit text and walking back to the declaration that
         * encloses it, rather than by matching a whole declaration in one pattern:
         * the map's copy is written as multi-line concatenations of string literals
         * — `POWERED_BY_ALERT` runs to eight of them — and a pattern that tried to
         * span an initialiser would have to model that. The position of the credit
         * relative to the declarations around it does not need modelling.
         */
        fun creditConstant(text: String, credit: String): String? {
            val at = text.indexOf(credit)
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
        val screen = fileNamed(SCREEN_FILE)

        // Both phrases are checked, and each one separately, because the failure this
        // guard exists to prevent is a *partial* credit: the half that is present is
        // exactly what makes the missing half easy to miss in review.
        for (credit in REQUIRED_CREDITS) {
            val constant = creditConstant(copy.code(), credit)

            assertTrue(
                "MapBasemap.STYLE_URI is set to '${literal.value}', so this app now draws " +
                    "the bittr basemap — but no constant in ${copy.repoPath()} carries the " +
                    "credit \"$credit\".\n" +
                    "The basemap has two upstreams and owes both: the data is " +
                    "OpenStreetMap's under ODbL, and the tiles are built with the " +
                    "OpenMapTiles schema under CC-BY. Crediting one is not crediting the " +
                    "other, and neither is satisfied by the existing BTCMap wording — that " +
                    "sentence credits OSM for where the *places* are tagged and covers no " +
                    "map imagery.\n" +
                    "The full pair is what the built archive's own PMTiles metadata " +
                    "declares, so this is not a reading of the licence text: it is the " +
                    "credit the artefact the app serves says it carries.\n" +
                    "This is done-when item 4 on BIT-119, and it is required in the same " +
                    "commit as the STYLE_URI change rather than in a follow-up. The wording " +
                    "around the credits is the Growth & Content Lead's to write (BIT-56 is " +
                    "the precedent, BIT-149 is the live issue); the credits themselves are " +
                    "the licences' and are not a copy decision.\n" +
                    "Read android/docs/tile-pipeline.md §3.",
                constant != null,
            )
            requireNotNull(constant)

            assertTrue(
                "MapCopy.$constant carries \"$credit\", but ${screen.repoPath()} never " +
                    "reads it — so the string exists and the screen does not show it, which " +
                    "is the same outcome as not having written it.\n" +
                    "Render it on the map surface, next to where MapCopy.POWERED_BY is " +
                    "rendered today.\n" +
                    "Note what this guard still cannot see: that the credit is legible once " +
                    "rendered. It reads a reference, not a pixel. Prove visibility with an " +
                    "assertion in the map module's Robolectric tests, where the rest of " +
                    "this screen is already checked without an emulator.\n" +
                    "It also cannot see MapLibre's built-in attribution control, and that " +
                    "control is not a substitute: on Android it is an (i) button whose " +
                    "credits appear only in a dialog after a tap, so it does not put either " +
                    "phrase on the map surface.",
                rendersCredit(screen.code(), constant),
            )
        }
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
            Result.Url(VERSIONED_STYLE),
            styleUriLiteral("""val STYLE_URI: String? = "$VERSIONED_STYLE""""),
        )

        for (credit in REQUIRED_CREDITS) {
            assertEquals(
                "The credit detector no longer finds \"$credit\" when it is present, so the " +
                    "guard would fail a commit that did everything right — and the fix for " +
                    "a guard that cries wolf is that someone deletes it.",
                "BASEMAP_ATTRIBUTION",
                creditConstant(CREDIT_LINE, credit),
            )

            assertEquals(
                "The credit detector attributes \"$credit\" to the wrong constant when " +
                    "several are declared, so the render check would look for a name that " +
                    "is not the one holding the string.",
                "BASEMAP_ATTRIBUTION",
                creditConstant(
                    """
                    const val TITLE: String = "Pay with bitcoin"
                    $CREDIT_LINE
                    const val CLOSE: String = "Close"
                    """.trimIndent(),
                    credit,
                ),
            )
        }

        assertEquals(
            "The OpenMapTiles detector accepts a credit that carries only the " +
                "OpenStreetMap half. This is the BIT-149 regression itself, not a " +
                "hypothetical one: that line is the wording BIT-140 approved, it is what " +
                "anyone writing this credit from the issue description would produce, and " +
                "while this assertion was absent the guard went green on it — reporting " +
                "that the licences were met in the one state where the CC-BY grant was not.",
            null,
            creditConstant(OSM_ONLY_CREDIT_LINE, OMT_CREDIT),
        )

        assertEquals(
            "The OpenStreetMap detector stopped seeing the OSM half of a line that has " +
                "only that half — which would mean the assertion above passes for the wrong " +
                "reason and no longer isolates the missing OpenMapTiles credit.",
            "BASEMAP_ATTRIBUTION",
            creditConstant(OSM_ONLY_CREDIT_LINE, OSM_CREDIT),
        )

        assertEquals(
            "The OpenMapTiles detector accepts a bare '© OpenMapTiles'. That is the form " +
                "planetiler and the archive metadata both show, so it is what anyone " +
                "writing this line from the upstream sources would reach for — but both " +
                "show it as a link, and this credit is an unclickable Text. Unlinked it " +
                "meets neither alternative in the CC-BY notice, so accepting it would be " +
                "the BIT-149 failure again one level down: green on a credit that does not " +
                "discharge the licence. See OMT_CREDIT on why the '.org' is pinned.",
            null,
            creditConstant(BARE_OMT_CREDIT_LINE, OMT_CREDIT),
        )

        assertEquals(
            "The OpenStreetMap detector stopped seeing the OSM half of the bare-OpenMapTiles " +
                "line, so the assertion above no longer isolates the OpenMapTiles credit.",
            "BASEMAP_ATTRIBUTION",
            creditConstant(BARE_OMT_CREDIT_LINE, OSM_CREDIT),
        )

        assertEquals(
            "The credit detector accepts the *places* credit as a basemap credit. That " +
                "sentence is already in the app, so the guard would pass the moment it armed " +
                "and would never have asked for anything.",
            null,
            creditConstant(
                """const val POWERED_BY_ALERT: String = "uses OpenStreetMap to tag places"""",
                OSM_CREDIT,
            ),
        )

        assertEquals(
            "The credit detector reports a credit in a file that has none, which would let " +
                "an absent credit satisfy the check.",
            null,
            creditConstant("""const val TITLE: String = "Pay with bitcoin"""", OSM_CREDIT),
        )

        assertEquals(
            "The credit detector accepts an HTML entity for the copyright sign. A Compose " +
                "Text renders that literally, so the guard would pass a build showing " +
                "'&copy; OpenStreetMap contributors' to the user.",
            null,
            creditConstant(ENTITY_CREDIT_LINE, OSM_CREDIT),
        )

        assertEquals(
            "The credit detector accepts '(c)' for the copyright sign. BIT-140 pinned " +
                "U+00A9 specifically, and a credit is a licence artefact whose exact form " +
                "is not the app's to restyle.",
            null,
            creditConstant(ASCII_CREDIT_LINE, OSM_CREDIT),
        )

        assertTrue(
            "The render detector no longer sees the credit constant being read, so a " +
                "correctly rendered credit would fail the guard.",
            rendersCredit(
                """Text(text = MapCopy.BASEMAP_ATTRIBUTION, style = small)""",
                "BASEMAP_ATTRIBUTION",
            ),
        )

        assertTrue(
            "The render detector reports a constant the screen never reads. A string " +
                "declared and never shown would pass — which is the exact failure this " +
                "guard exists to catch, one step further along.",
            !rendersCredit(
                """Text(text = MapCopy.POWERED_BY, style = small)""",
                "BASEMAP_ATTRIBUTION",
            ),
        )
    }
}
