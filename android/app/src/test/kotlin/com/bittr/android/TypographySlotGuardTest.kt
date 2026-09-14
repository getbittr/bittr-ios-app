package com.bittr.android

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import com.bittr.android.core.designsystem.BittrTypography
import com.bittr.android.core.designsystem.Gilroy
import com.bittr.android.SourceTree.codeWithoutLiterals
import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Every Material 3 type slot a screen reads must be one `BittrTypography` fills in.
 *
 * `Typography` has fifteen slots and [BittrTypography] sets nine. The other six keep
 * M3's own defaults, and those defaults are `FontFamily.SansSerif` — the platform
 * face, at sizes the scale never chose. Reading one is not a compile error, not a
 * lint warning, and not visible in a test that asserts on text content: the screen
 * renders, the words are right, and the face is wrong. BIT-151 found four such reads
 * only because someone measured a credit line in pixels.
 *
 * The rule this enforces is the one `Type.kt` already states — Gilroy is *"the only
 * font family in the app"*, and *"every size in the app comes from this scale"*. A
 * read of an unfilled slot breaks both at once, and is the one way to break them
 * that leaves no trace at the call site.
 *
 * **Which slots count as filled is derived, not listed.** The check asks each slot
 * what family it carries and treats "Gilroy" as filled, so adding a scale entry
 * makes it legal here with no second edit, and deleting one turns its call sites red
 * rather than silently handing them to the platform font. There is no allowlist to
 * drift.
 *
 * What it does not cover: a hard-coded `TextStyle(fontSize = 12.sp)` at a call site
 * bypasses the scale without naming a slot, so it bypasses this guard too. That is a
 * different shape of the same mistake and wants a different check; this one is
 * written down as covering the slot reads.
 */
class TypographySlotGuardTest {

    private companion object {
        /**
         * `MaterialTheme.typography.<slot>`, and the bare `typography.<slot>` that a
         * `with(MaterialTheme)` scope allows.
         *
         * Lower-case `t` on purpose: it distinguishes the *read* from the type name
         * and from `BittrTypography`, so the scale's own definition site does not
         * register as a call site.
         */
        val SLOT_READ = Regex("""\btypography\.([A-Za-z]+)""")
    }

    /**
     * Each slot on [BittrTypography], read back through the accessors `Typography`
     * exposes rather than from a list kept here.
     *
     * Java reflection, not `memberProperties` — the guards run on the plain JUnit
     * classpath and `kotlin-reflect` is not on it.
     */
    private val slots: Map<String, TextStyle> by lazy {
        val accessors = Typography::class.java.methods
            .filter {
                it.parameterCount == 0 &&
                    it.returnType == TextStyle::class.java &&
                    it.name.startsWith("get") &&
                    // `getBodyLargeEmphasized$material3` and its eight siblings are
                    // name-mangled internal accessors, derived from the public slot
                    // rather than settable. Kotlin cannot name them at a call site,
                    // so they are not slot reads and listing them in a failure would
                    // only make it harder to read.
                    '$' !in it.name
            }
        assertTrue(
            "Found no TextStyle accessors on ${Typography::class.java.name}. The slot set " +
                "is read off the class, so an empty one would make every check below pass " +
                "without looking at anything.",
            accessors.isNotEmpty(),
        )
        accessors.associate { accessor ->
            accessor.name.removePrefix("get").replaceFirstChar { it.lowercaseChar() } to
                accessor.invoke(BittrTypography) as TextStyle
        }
    }

    /** The slots the scale fills. The rest are M3's platform-font defaults. */
    private val filled: Set<String> by lazy {
        slots.filterValues { it.fontFamily == Gilroy }.keys
    }

    @Test
    fun `the scale fills the slots its own documentation names`() {
        // Not the whole set — a guard that restates the scale would have to be
        // edited every time the scale grows. These are the ones `Type.kt`'s
        // convention table sends call sites to by name, so losing one silently
        // would redirect documented usage to the platform font.
        val documented = setOf("labelLarge", "bodyLarge", "bodyMedium", "titleMedium", "labelMedium")
        assertEquals(
            "BittrTypography no longer fills slots that Type.kt's convention table tells " +
                "call sites to use. Anything reading them now draws in FontFamily.SansSerif " +
                "at an M3 default size.",
            emptySet<String>(),
            documented - filled,
        )
    }

    @Test
    fun `no screen reads a slot the scale leaves at its Material default`() {
        val violations = mutableListOf<String>()

        SourceTree.kotlinSources().forEach { file ->
            SLOT_READ.findAll(file.codeWithoutLiterals()).forEach { match ->
                val slot = match.groupValues[1]
                // An unknown name is not a slot at all — `typography.copy(...)` and
                // the like. Only the fifteen real ones are judged.
                if (slot in slots && slot !in filled) {
                    violations += "${file.repoPath()} reads typography.$slot"
                }
            }
        }

        assertEquals(
            "These call sites read a type slot BittrTypography does not fill, so they draw " +
                "in the platform sans-serif at an M3 default size instead of Gilroy at a " +
                "size the scale chose. Nothing else fails when this happens — see BIT-151, " +
                "where four of them had been shipping. Fix by moving the call site to a " +
                "filled slot (Type.kt's convention table says which), or by filling the " +
                "slot in BittrTypography if the design system really wants that size. " +
                "Slots currently filled: ${filled.sorted()}.",
            emptyList<String>(),
            violations.sorted(),
        )
    }

    @Test
    fun `the scan finds the slot reads it is meant to be judging`() {
        // A source-scan guard that matches nothing passes. This one would then be
        // reporting "no screen reads an unfilled slot" about a tree it never read.
        val found = SourceTree.kotlinSources()
            .flatMap { SLOT_READ.findAll(it.codeWithoutLiterals()).map { m -> m.groupValues[1] } }
            .filter { it in slots }
            .toSet()
        assertTrue(
            "The scan matched no type slot reads anywhere under ${SourceTree.root}. Either " +
                "the tree moved or the call shape changed; either way this guard is no " +
                "longer checking anything.",
            found.size >= 5,
        )
    }
}
