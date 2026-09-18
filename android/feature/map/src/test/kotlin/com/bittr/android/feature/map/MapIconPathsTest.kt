package com.bittr.android.feature.map

import androidx.core.graphics.PathParser
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.designsystem.normalizeSvgPath
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The map's own glyphs parse with the strict parser the pin bitmap uses. [MapIconPaths.BITCOIN]
 * is the one that crashed the app on opening the map (2026-09-18); `SvgPathTest` covers the
 * design system's set.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class MapIconPathsTest {

    @Test
    fun `every MapIconPaths constant parses with the strict parser`() {
        val paths = MapIconPaths::class.java.declaredFields
            .filter { it.type == String::class.java }
            .onEach { it.isAccessible = true }
            .associate { it.name to it.get(null) as String }
        assertTrue("found no map icon paths", paths.size >= 5)
        for ((name, data) in paths) {
            val parsed = runCatching { PathParser.createPathFromPathData(normalizeSvgPath(data)) }
            assertTrue("MapIconPaths.$name does not parse: ${parsed.exceptionOrNull()}", parsed.getOrNull() != null)
        }
    }
}
