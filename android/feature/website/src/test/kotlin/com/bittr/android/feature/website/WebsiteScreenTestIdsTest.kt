package com.bittr.android.feature.website

import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * `website.downButton` exists, is displayed, is a full-size touch target, and
 * closes the screen.
 *
 * Two shared Maestro flows depend on it —
 * `shared/flows/features/bitcoin_map.yaml:110–123` and
 * `shared/flows/features/swap.yaml:387–393` — each of which taps it to leave the
 * browser and then asserts the screen underneath. If the tag is missing, both
 * flows fail after an emulator boot with "element not found", which looks
 * identical to a broken emulator. This says which tag went missing, in seconds,
 * on the JVM.
 *
 * It is also the reason S-36 is an in-app WebView rather than a `CustomTabsIntent`
 * as BIT-21 preferred: a Custom Tab has no such element and no way to be given
 * one.
 *
 * What this cannot cover is `testTagsAsResourceId`, set on the root in
 * `MainActivity` — Robolectric reads the Compose semantics tree directly and
 * passes either way. Only the emulator run proves that half.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class WebsiteScreenTestIdsTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun `exposes website_downButton and closes on tap`() {
        var closed = 0

        composeRule.setContent {
            BittrTheme {
                WebsiteScreen(
                    url = "https://getbittr.com/support",
                    onClose = { closed++ },
                )
            }
        }

        composeRule.onNodeWithTag(TestID.Website.downButton).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Website.downButton).performClick()

        assertEquals("Tapping website.downButton must dismiss the screen.", 1, closed)
    }

    @Test
    fun `the close button is a full-size touch target`() {
        // The spec is a 20x20 chevron inside a 40x40 target. Sizing the button to
        // the icon is the easy mistake, and it halves the target on the control
        // both Maestro flows tap — and on a small unlabelled affordance in the
        // corner of a browser, which is where the accessibility guidance's 48dp
        // minimum comes from in the first place.
        composeRule.setContent {
            BittrTheme {
                WebsiteScreen(url = "https://getbittr.com/support", onClose = {})
            }
        }

        composeRule.onNodeWithTag(TestID.Website.downButton)
            .assertWidthIsAtLeast(40.dp)
            .assertHeightIsAtLeast(40.dp)
    }

    @Test
    fun `renders a third-party url without incident`() {
        // The BTCMap case. Nothing here asserts what the page can do — that needs a
        // real renderer and lives in the instrumented isolation tests — but the
        // screen must compose for an arbitrary third-party URL rather than only for
        // the first-party one.
        composeRule.setContent {
            BittrTheme {
                WebsiteScreen(url = "https://merchant.example/menu", onClose = {})
            }
        }

        composeRule.onNodeWithTag(TestID.Website.downButton).assertIsDisplayed()
    }
}
