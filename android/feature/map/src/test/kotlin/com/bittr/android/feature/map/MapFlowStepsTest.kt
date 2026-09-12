package com.bittr.android.feature.map

import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.core.common.TestID
import com.bittr.android.core.designsystem.BittrTheme
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * `shared/flows/features/bitcoin_map.yaml`, step for step, on the JVM.
 *
 * The renderer is stubbed — see the note on the internal [MapScreen] — so
 * `map.mapView` here is a placeholder carrying the right identifier rather than a
 * real map. Every other step is the app's own code over its own data, and each one
 * is a place the flow can fail without the screen looking wrong.
 *
 * Not covered, and only an emulator can: that the basemap draws, and that the tags
 * are bridged onto the accessibility tree.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp-420dpi")
class MapFlowStepsTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val synced = CompletableDeferred<List<BitcoinPlace>>()

    private fun place(
        id: Int,
        name: String,
        lat: Double,
        lon: Double,
        website: String? = null,
        address: String? = null,
    ) = BitcoinPlace(
        id = id,
        lat = lat,
        lon = lon,
        icon = "local_cafe",
        name = name,
        address = address,
        updatedAt = null,
        deletedAt = null,
        website = website,
        openingHours = "Mo-Fr 08:00-18:00",
    )

    /**
     * Two places inside the default Switzerland region, as a first sync would return.
     *
     * **The list is drawn nearest-first, not in response order** — `nearby()` sorts by
     * distance from the map centre, as `sortByProximity` does on iOS — so these are
     * named for where they land rather than for where they are declared. Bern is
     * about 62 km from the default centre and Zürich about 68 km. The flow taps
     * `index: 0`, so which one that is matters.
     */
    private val nearest = place(2, "Bäckerei Block", 46.9480, 7.4474)
    private val farther = place(
        1,
        "Café Satoshi",
        47.3769,
        8.5417,
        website = "https://www.example.com/",
        address = "Bahnhofstrasse 1",
    )
    private val places = listOf(farther, nearest)

    private val repository = object : PlacesRepository {
        override suspend fun cached(): List<BitcoinPlace> = emptyList()
        override suspend fun sync(): List<BitcoinPlace> = synced.await()
    }

    private fun mapScreen() {
        composeRule.setContent {
            BittrTheme {
                MapScreen(
                    onBack = {},
                    repository = repository,
                    basemap = { _, _, _, modifier -> Box(modifier) },
                )
            }
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
    fun `the map and its spinner are on screen before the sync returns`() {
        mapScreen()

        // - assertVisible: id: "map.mapView"
        composeRule.onNodeWithTag(TestID.Map.mapView).assertIsDisplayed()
        // The flow waits for map.mapSpinner to go, so it has to be there first.
        composeRule.onNodeWithTag(TestID.Map.mapSpinner).assertIsDisplayed()
        assertTrue(
            "No place cells until there are places; an empty list here would let the " +
                "flow's assertVisible pass against a stale row.",
            tagIsGone(TestID.Map.placeName),
        )
    }

    @Test
    fun `the BTCMap credit opens the approved alert and closes again`() {
        mapScreen()

        // - tapOn: id: "map.poweredByButton"
        composeRule.onNodeWithTag(TestID.Map.poweredByButton).assertIsDisplayed().performClick()
        // - assertVisible: id: "alert.button.0"
        awaitTag(TestID.Alert.buttonAt(0))
        // - tapOn: alert.button.0  → gone
        composeRule.onNodeWithTag(TestID.Alert.buttonAt(0)).performClick()
        composeRule.waitForIdle()
        assertTrue(tagIsGone(TestID.Alert.buttonAt(0)))
    }

    @Test
    fun `the sync populates the places table`() {
        mapScreen()
        synced.complete(places)

        // - extendedWaitUntil: notVisible map.mapSpinner
        composeRule.waitUntil(TIMEOUT_MS) { tagIsGone(TestID.Map.mapSpinner) }
        // - assertVisible: id: "map.placeName"
        awaitTag(TestID.Map.placeName)
        composeRule.onNodeWithTag(TestID.Map.placesTableView).assertIsDisplayed()

        assertEquals(
            "Every cell carries both identifiers, as on iOS — the flow taps index 0, so " +
                "they repeat rather than being unique.",
            places.size,
            composeRule.onAllNodesWithTag(TestID.Map.placeCellButton).fetchSemanticsNodes().size,
        )
    }

    @Test
    fun `the table is ordered nearest first`() {
        assertEquals(
            "The flow taps index 0 and screenshots what opens. Response order would make " +
                "that whichever row BTCMap happened to return first.",
            listOf(nearest.name, farther.name),
            MapUiState(allPlaces = places).withPlacesForRegion().visiblePlaces.map { it.name },
        )
    }

    @Test
    fun `opening a place shows its sheet and closes`() {
        mapScreen()
        synced.complete(places)
        awaitTag(TestID.Map.placeCellButton)

        // - tapOn: id: "map.placeCellButton" index 0 — the nearest place.
        composeRule.onAllNodesWithTag(TestID.Map.placeCellButton)[0].performClick()
        // - assertVisible: id: "map.onePlace.nameLabel"
        awaitTag(TestID.Map.OnePlace.nameLabel)
        composeRule.onNodeWithTag(TestID.Map.OnePlace.goToMapsButton).assertIsDisplayed()

        // - tapOn: map.onePlace.closeButton → assertNotVisible map.onePlace.nameLabel
        composeRule.onNodeWithTag(TestID.Map.OnePlace.closeButton).performClick()
        composeRule.waitForIdle()
        assertTrue(tagIsGone(TestID.Map.OnePlace.nameLabel))
    }

    /**
     * The flow's website section, which it guards on the button being visible:
     *
     * ```
     * - runFlow:
     *     when: { visible: { id: "map.onePlace.websiteButton" } }
     * ```
     *
     * Both halves are checked, because the guard is only worth anything if the button
     * is genuinely absent for a place with no website. One that always drew the row
     * would send the flow into an in-app browser with nothing to load.
     */
    @Test
    fun `the website opens in-app when the place has one`() {
        mapScreen()
        synced.complete(places)
        awaitTag(TestID.Map.placeCellButton)

        composeRule.onAllNodesWithTag(TestID.Map.placeCellButton)[0].performClick()
        awaitTag(TestID.Map.OnePlace.nameLabel)
        assertTrue(
            "The nearest place lists no website, so the flow skips its website section.",
            tagIsGone(TestID.Map.OnePlace.websiteButton),
        )
        composeRule.onNodeWithTag(TestID.Map.OnePlace.closeButton).performClick()
        composeRule.waitForIdle()

        composeRule.onAllNodesWithTag(TestID.Map.placeCellButton)[1].performClick()
        awaitTag(TestID.Map.OnePlace.websiteButton)

        composeRule.onNodeWithTag(TestID.Map.OnePlace.websiteButton).performClick()
        // - assertVisible: id: "website.downButton"
        awaitTag(TestID.Website.downButton)
        // - tapOn: website.downButton → assertVisible map.onePlace.nameLabel
        composeRule.onNodeWithTag(TestID.Website.downButton).performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag(TestID.Map.OnePlace.nameLabel).assertIsDisplayed()
    }

    @Test
    fun `the my-location button is there for the flow to tap`() {
        mapScreen()
        synced.complete(places)
        awaitTag(TestID.Map.placeName)

        // - tapOn: map.userLocationButton  → assertVisible map.mapView
        composeRule.onNodeWithTag(TestID.Map.userLocationButton).assertIsDisplayed().performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag(TestID.Map.mapView).assertIsDisplayed()
    }

    private companion object {
        const val TIMEOUT_MS = 10_000L
    }
}
