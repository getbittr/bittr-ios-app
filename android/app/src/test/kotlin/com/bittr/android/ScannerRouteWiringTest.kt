package com.bittr.android

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Keeps the scanner route wired to the parser.
 *
 * `ScannerSeamTest` proves that [com.bittr.android.navigation.ScannerResult.handleScan]
 * does the right thing. It cannot prove that the navigation graph still *calls* it —
 * the real scanner route needs a camera and a Hilt view model, so it is not driven on
 * the JVM. This closes that gap by reading the graph.
 *
 * The failure this exists to catch is a quiet one and it has already happened once.
 * BIT-72 shipped the route as:
 *
 * ```kotlin
 * ScannerScreen(
 *     onScanned = { navController.popBackStack() },
 * ```
 *
 * which compiles, scans, closes cleanly, and silently discards what it read — the
 * `onScanned` parameter is not even named, so nothing looks wrong. That was correct
 * at the time, because Send did not exist to receive it. Once Send does, the same
 * line would be a scanner that appears to work and never fills in an address, and
 * there is no test that would go red except this one.
 */
class ScannerRouteWiringTest {

    private val navHost: File
        get() = File(
            SourceTree.root,
            "app/src/main/kotlin/com/bittr/android/navigation/BittrNavHost.kt",
        ).also {
            assertTrue("Expected the navigation graph at $it", it.isFile)
        }

    @Test
    fun `the scanner route hands its result to ScannerResult`() {
        val source = navHost.readText()
        val route = scannerRouteBody(source)

        assertTrue(
            "The scanner route no longer calls ScannerResult.handleScan. Whatever " +
                "replaced it must still deliver the scanned code to the caller — a " +
                "scanner whose result is dropped is BIT-72's open seam reopened, and it " +
                "fails as a Send screen that never fills in an address.\n\nRoute body:\n$route",
            route.contains("ScannerResult.handleScan"),
        )
    }

    @Test
    fun `the scanner route does not simply pop on a successful scan`() {
        val route = scannerRouteBody(navHost.readText())

        // `onClose` legitimately pops and nothing else. `onScanned` must not.
        val onScanned = route.substringAfter("onScanned").substringBefore("onClose")
        assertFalse(
            "onScanned pops the back stack without delivering anything, which drops the " +
                "scan. onClose may do that; onScanned may not.\n\nonScanned:\n$onScanned",
            onScanned.replace(Regex("\\s"), "") == "={navController.popBackStack()},",
        )
    }

    /** The `composable(Routes.SCANNER) { … }` block, by brace matching. */
    private fun scannerRouteBody(source: String): String {
        val marker = "composable(Routes.SCANNER)"
        val start = source.indexOf(marker)
        assertTrue(
            "No `composable(Routes.SCANNER)` in the navigation graph. If the scanner " +
                "moved to a nested graph, point this test at it rather than deleting it.",
            start >= 0,
        )

        var depth = 0
        var i = source.indexOf('{', start)
        val open = i
        while (i < source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return source.substring(open, i + 1)
                }
            }
            i++
        }
        error("Unbalanced braces in ${navHost.name} from offset $start")
    }
}
