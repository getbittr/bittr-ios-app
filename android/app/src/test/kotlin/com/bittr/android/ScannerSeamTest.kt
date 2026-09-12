package com.bittr.android

import androidx.activity.compose.setContent
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.destination.BitcoinNetwork
import com.bittr.android.core.common.destination.Destination
import com.bittr.android.navigation.Routes
import com.bittr.android.navigation.ScannerResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The seam BIT-72 left open and BIT-100 closes: a scanned QR reaches the screen that
 * opened the scanner, instead of being popped off the back stack and dropped.
 *
 * BIT-72's own tests cover the scanner — permission states, the decoder, the screen.
 * None of them could cover this, because until now there was nothing on the other
 * side of the callback. What is asserted here is the round trip: decoded string in,
 * parsed [Destination] out, on the caller's back stack entry, with the scanner gone.
 *
 * The graph below is a stand-in for the real one. `BittrNavHost` needs a Hilt view
 * model and, more to the point, the scanner route would need a camera; the logic
 * under test — [ScannerResult.handleScan] — is the same function the real route
 * calls, which is why it is a named function and not a lambda in the graph.
 * `ScannerRouteWiringTest` is what keeps those two facts from drifting apart.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class ScannerSeamTest {

    /**
     * [MainActivity] rather than `createComposeRule()`, so this runs on the release
     * unit-test variant too — see [ComposeRuleVariantGuardTest] for why the bare
     * rule cannot. The graph below still replaces the activity's own content, so
     * what is under test is unchanged.
     */
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    /** Minted with the BIP-173 reference implementation; regtest, as the debug build is. */
    private val regtestAddress = "bcrt1qt8t4ycw8eld5taqqh2ug7mhq3pwu3dpvxl25fw"

    private lateinit var navController: NavHostController

    private fun openScanner() {
        composeRule.runOnUiThread {
            composeRule.activity.setContent {
                val controller = rememberNavController()
                SideEffect { navController = controller }
                NavHost(navController = controller, startDestination = CALLER) {
                    composable(CALLER) {}
                    composable(Routes.SCANNER) {}
                }
            }
        }
        composeRule.runOnIdle { navController.navigate(Routes.SCANNER) }
        composeRule.runOnIdle {
            assertEquals(Routes.SCANNER, navController.currentBackStackEntry?.destination?.route)
        }
    }

    @Test
    fun `a scanned address reaches the caller as a parsed destination`() {
        openScanner()

        composeRule.runOnIdle {
            ScannerResult.handleScan(navController, regtestAddress, BitcoinNetwork.REGTEST)
        }

        composeRule.runOnIdle {
            // The scanner closed itself, as `send_onchain.yaml:83-85` expects.
            assertEquals(CALLER, navController.currentBackStackEntry?.destination?.route)

            // …and left the result behind, parsed rather than raw.
            val handle = navController.currentBackStackEntry!!.savedStateHandle
            assertEquals(
                Destination.OnChain(regtestAddress),
                ScannerResult.consume(handle),
            )
        }
    }

    @Test
    fun `a scanned BIP-21 URI arrives with its amount`() {
        openScanner()

        composeRule.runOnIdle {
            ScannerResult.handleScan(
                navController,
                "bitcoin:$regtestAddress?amount=0.0015",
                BitcoinNetwork.REGTEST,
            )
        }

        composeRule.runOnIdle {
            val handle = navController.currentBackStackEntry!!.savedStateHandle
            assertEquals(
                Destination.OnChain(regtestAddress, amountSats = 150_000L),
                ScannerResult.consume(handle),
            )
        }
    }

    @Test
    fun `an unreadable QR is delivered as Unrecognised rather than swallowed`() {
        // The caller has to tell the user "no bitcoin address found". It cannot do
        // that if a failed scan looks exactly like the user pressing Back.
        openScanner()

        composeRule.runOnIdle {
            ScannerResult.handleScan(navController, "not a bitcoin anything", BitcoinNetwork.REGTEST)
        }

        composeRule.runOnIdle {
            val handle = navController.currentBackStackEntry!!.savedStateHandle
            assertEquals(Destination.Unrecognised, ScannerResult.consume(handle))
        }
    }

    @Test
    fun `consuming a result clears it`() {
        // Send recomposes for reasons that have nothing to do with scanning. A result
        // left in place would refill the address field after the user cleared it.
        openScanner()

        composeRule.runOnIdle {
            ScannerResult.handleScan(navController, regtestAddress, BitcoinNetwork.REGTEST)
        }

        composeRule.runOnIdle {
            val handle = navController.currentBackStackEntry!!.savedStateHandle
            assertTrue(ScannerResult.consume(handle) is Destination.OnChain)
            assertNull(ScannerResult.consume(handle))
        }
    }

    private companion object {
        const val CALLER = "caller"
    }
}
