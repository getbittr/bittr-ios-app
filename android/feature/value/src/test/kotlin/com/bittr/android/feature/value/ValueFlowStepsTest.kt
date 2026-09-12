package com.bittr.android.feature.value

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * `shared/flows/features/bitcoin_value.yaml`, step for step, on the JVM.
 *
 * The flow's own comments spell out the ordering it depends on: the graph exists
 * before the data does, the spinner and the profit badge flip together, and span
 * taps before that are dropped. All three are properties of this composition, so all
 * three are checked here rather than on an emulator — where a dropped tap looks like
 * a flaky run.
 *
 * The repository is a deferred one, so the test can hold the screen in its loading
 * state and assert what is and is not on screen *while the fetch is in flight* —
 * which is the state the flow's `extendedWaitUntil` exists for and the one a
 * screenshot cannot show.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
class ValueFlowStepsTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val loaded = CompletableDeferred<PriceSnapshot>()

    private val repository = object : PriceRepository {
        override suspend fun load(currency: PriceCurrency, today: LocalDate) = loaded.await()
    }

    private fun snapshot(): PriceSnapshot {
        val now = Instant.parse("2026-09-12T12:00:00Z")
        val series = GraphSpan.entries.associateWith { span ->
            (0..9).map { step ->
                PricePoint(
                    at = now.minusSeconds((10L - step) * 86_400),
                    price = 90_000.0 + step * 1_000 + span.ordinal * 10,
                )
            }
        }
        return PriceSnapshot(series = series, currentPrice = 99_000.0)
    }

    private fun valueScreen() {
        composeRule.setContent {
            BittrTheme { ValueScreen(onBack = {}, repository = repository) }
        }
    }

    private fun awaitTag(tag: String) {
        composeRule.waitUntil(TIMEOUT_MS) {
            composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun tagIsGone(tag: String) =
        composeRule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()

    @Test
    fun `the graph is on screen before the data is`() {
        valueScreen()

        // - assertVisible: id: "value.graphView" — asserted immediately after the tap
        // from Home, long before the two price requests return.
        composeRule.onNodeWithTag(TestID.Value.graphView).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Value.valueSpinner).assertIsDisplayed()
        assertTrue(
            "profitLabel is the flow's \"data loaded\" signal. On screen during the " +
                "fetch, extendedWaitUntil returns immediately and the span taps that " +
                "follow are dropped — which fails as three screenshots of the same chart.",
            tagIsGone(TestID.Value.profitLabel),
        )
    }

    @Test
    fun `the spinner and the profit badge flip together`() {
        valueScreen()
        composeRule.onNodeWithTag(TestID.Value.valueSpinner).assertIsDisplayed()

        loaded.complete(snapshot())

        // - extendedWaitUntil: visible value.profitLabel
        awaitTag(TestID.Value.profitLabel)
        // - assertNotVisible: id: "value.valueSpinner"
        assertTrue(tagIsGone(TestID.Value.valueSpinner))
        // - assertVisible: value.currentValueLabel, value.profitLabel
        composeRule.onNodeWithTag(TestID.Value.currentValueLabel).assertIsDisplayed()
        composeRule.onNodeWithTag(TestID.Value.profitLabel).assertIsDisplayed()
    }

    @Test
    fun `the span buttons switch the chart once the data has landed`() {
        valueScreen()
        loaded.complete(snapshot())
        awaitTag(TestID.Value.profitLabel)

        // - tapOn: value.monthButton / yearButton / fiveYearsButton, each followed by
        //   assertVisible value.graphView.
        listOf(
            TestID.Value.monthButton,
            TestID.Value.yearButton,
            TestID.Value.fiveYearsButton,
        ).forEach { tag ->
            composeRule.onNodeWithTag(tag).performClick()
            composeRule.waitForIdle()
            composeRule.onNodeWithTag(TestID.Value.graphView).assertIsDisplayed()
        }
    }

    /**
     * The guard the flow's step ordering exists for. `changeSpan` returns early while
     * `isFetchingData` is true, so a tap during the fetch does nothing — which is why
     * the flow waits for `value.profitLabel` before tapping m, y and 5y.
     */
    @Test
    fun `a span tap during the fetch is dropped`() {
        val fetching = ValueUiState(isFetchingData = true)
        assertEquals(GraphSpan.WEEK, fetching.selectSpan(GraphSpan.YEAR).selectedSpan)

        val loadedState = fetching.copy(isFetchingData = false)
        assertEquals(GraphSpan.YEAR, loadedState.selectSpan(GraphSpan.YEAR).selectedSpan)
    }

    /**
     * The scrub card is torn down on finger-lift (`touchesEnded`), which the flow
     * documents as the reason it cannot assert `value.graphValueLabel` after the
     * swipe. Asserted here from the other side: it is absent with no gesture in
     * progress, so the flow's comment describes the Android screen too.
     */
    @Test
    fun `the scrub card exists only during the gesture`() {
        valueScreen()
        loaded.complete(snapshot())
        awaitTag(TestID.Value.profitLabel)

        assertTrue(tagIsGone(TestID.Value.graphValueLabel))
    }

    private companion object {
        const val TIMEOUT_MS = 10_000L
    }
}
