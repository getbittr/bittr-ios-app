package com.bittr.android

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import com.bittr.android.feature.home.HomeNoFunds
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The first step of each Wave 1 flow: leaving Home.
 *
 * `bitcoin_value.yaml`, `bitcoin_map.yaml` and `academy.yaml` all unlock, land on
 * Home, and tap one identifier to get where they are going —
 * `home.currencyButton`, `home.mapButton` and `nav.academyButton`. Three screens can
 * be complete and every one of those flows still fails at that tap, with the same
 * "element not found" a broken screen produces.
 *
 * Two halves, because neither is enough alone. The composed half proves the
 * identifiers are on Home and are clickable; the source half proves the click leads
 * to the right destination, which composing Home cannot show — its callbacks are
 * supplied by the navigation graph.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
class Wave1ReachabilityTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun `home carries the three identifiers the Wave 1 flows tap`() {
        val opened = mutableListOf<String>()
        composeRule.setContent {
            BittrTheme {
                HomeNoFunds(
                    onCurrency = { opened += "value" },
                    onMap = { opened += "map" },
                    onAcademy = { opened += "academy" },
                )
            }
        }

        // Every flow gates on this one first.
        composeRule.onNodeWithTag(TestID.Home.headerLabel).assertIsDisplayed()

        composeRule.onNodeWithTag(TestID.Home.currencyButton).assertIsDisplayed().performClick()
        composeRule.onNodeWithTag(TestID.Home.mapButton).assertIsDisplayed().performClick()
        composeRule.onNodeWithTag(TestID.Nav.academyButton).assertIsDisplayed().performClick()

        assertEquals(
            "Each identifier has to reach its own callback. Wiring two of them to the " +
                "same one compiles, looks right, and sends a flow to the wrong screen.",
            listOf("value", "map", "academy"),
            opened,
        )
    }

    @Test
    fun `home's entry points are wired to the three routes`() {
        val home = homeRouteBody(navHost.readText())

        listOf(
            "onCurrency" to "Routes.VALUE",
            "onMap" to "Routes.MAP",
            "onAcademy" to "Routes.ACADEMY",
        ).forEach { (parameter, route) ->
            val call = home.substringAfter(parameter, "")
            assertTrue(
                "Home's `$parameter` does not navigate to $route. The identifier is on " +
                    "screen and the tap goes nowhere, which fails as \"element not found\" " +
                    "on the *next* step of the flow rather than on this one.\n\nHome route:\n$home",
                call.substringBefore("\n").contains(route),
            )
        }
    }

    @Test
    fun `each Wave 1 route composes its screen`() {
        val source = navHost.readText()

        listOf(
            "Routes.VALUE" to "ValueScreen(",
            "Routes.MAP" to "MapScreen(",
            "Routes.ACADEMY" to "AcademyScreen(",
        ).forEach { (route, screen) ->
            val body = routeBody(source, "composable($route)")
            assertTrue(
                "The $route destination no longer composes $screen. A destination that " +
                    "registers and draws nothing is the shape a merge conflict resolves " +
                    "into, and it navigates successfully to a blank screen.\n\n$body",
                screen in body,
            )
        }
    }

    private val navHost: File
        get() = File(
            SourceTree.root,
            "app/src/main/kotlin/com/bittr/android/navigation/BittrNavHost.kt",
        ).also { assertTrue("Expected the navigation graph at $it", it.isFile) }

    private fun homeRouteBody(source: String) = routeBody(source, "composable(Routes.HOME)")

    /** The `composable(...) { … }` block at [marker], by brace matching. */
    private fun routeBody(source: String, marker: String): String {
        val start = source.indexOf(marker)
        assertTrue(
            "No `$marker` in the navigation graph. If the destination moved to a nested " +
                "graph, point this test at it rather than deleting it.",
            start >= 0,
        )

        var depth = 0
        var index = source.indexOf('{', start)
        val open = index
        while (index < source.length) {
            when (source[index]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return source.substring(open, index + 1)
                }
            }
            index++
        }
        error("Unbalanced braces in BittrNavHost.kt from offset $start")
    }
}
