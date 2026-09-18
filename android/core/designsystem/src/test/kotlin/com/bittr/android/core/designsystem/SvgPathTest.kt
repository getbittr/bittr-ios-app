package com.bittr.android.core.designsystem

import androidx.core.graphics.PathParser
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Every icon path the app draws parses with `androidx.core`'s [PathParser], the strict one
 * that threw on the map pin's compressed arc flags and crashed the app when the map opened
 * (2026-09-18). [normalizeSvgPath] is what makes them parse; this is what keeps a new
 * constant from reaching a device unparsed.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class SvgPathTest {

    @Test
    fun `compressed arc flags are split off`() {
        assertEquals(
            "M 8 5.5 h 5.2 a 3.1 3.1 0 0 1 0 6.2 H 8 z",
            normalizeSvgPath("M8 5.5h5.2a3.1 3.1 0 010 6.2H8z"),
        )
        assertEquals("a 8 8 0 1 1 -3 2", normalizeSvgPath("a8 8 0 11-3 2"))
    }

    @Test
    fun `run-together numbers and exponents survive`() {
        assertEquals("M 1.5 .5 L -2 3e-2", normalizeSvgPath("M1.5.5L-2,3e-2"))
    }

    @Test
    fun `the crashing glyph parses once normalised`() {
        val crashed = "M8 5.5h5.2a3.1 3.1 0 010 6.2H8z M8 11.7h6a3.4 3.4 0 010 6.8H8z"
        assertTrue(PathParser.createPathFromPathData(normalizeSvgPath(crashed)) != null)
    }

    @Test
    fun `every BittrIconPaths constant parses with the strict parser`() {
        val paths = BittrIconPaths::class.java.declaredFields
            .filter { it.type == String::class.java }
            .onEach { it.isAccessible = true }
            .associate { it.name to it.get(null) as String }
        assertTrue("found no icon paths — did BittrIconPaths move?", paths.size > 10)
        for ((name, data) in paths) {
            val parsed = runCatching { PathParser.createPathFromPathData(normalizeSvgPath(data)) }
            assertTrue("BittrIconPaths.$name does not parse: ${parsed.exceptionOrNull()}", parsed.getOrNull() != null)
        }
    }
}
