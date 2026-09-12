package com.bittr.android.feature.map

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The BTCMap sync: what the request asks for, how a response folds into the cache,
 * and which places end up on screen.
 *
 * Robolectric because `org.json` is an Android API with no implementation on a plain
 * JVM — the stub throws rather than parsing, which would make these pass or fail for
 * the wrong reason.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class PlacesSyncTest {

    private fun place(
        id: Int,
        lat: Double? = 46.8,
        lon: Double? = 8.2,
        name: String? = "Place $id",
        updatedAt: String? = null,
        deletedAt: String? = null,
    ) = BitcoinPlace(
        id = id,
        lat = lat,
        lon = lon,
        icon = "local_cafe",
        name = name,
        address = null,
        updatedAt = updatedAt,
        deletedAt = deletedAt,
        website = null,
        openingHours = null,
    )

    /**
     * The request shape is a compliance constraint — `mapvcpoweredbyalert` says the
     * phone downloads the whole list and filters it itself, and that claim was
     * checked against this URL on BIT-70. `MapSdkGuardTest` scans for the words a
     * narrowing query would use; this asserts the positive half, that the request
     * really does carry only the three parameters iOS sends.
     */
    @Test
    fun `the sync request describes no part of the world`() {
        val url = bitcoinMapUrl(updatedSince = null, includeDeleted = false)

        val query = url.substringAfter("?")
        val keys = query.split("&").map { it.substringBefore("=") }.toSet()
        assertEquals(
            "Only the parameters iOS sends (BitcoinPlace.swift:37-55). Anything else " +
                "needs to be checked against the approved copy before it ships.",
            setOf("fields", "include_deleted"),
            keys,
        )

        val withWatermark = bitcoinMapUrl(updatedSince = "2026-09-01T00:00:00Z", includeDeleted = true)
        assertEquals(
            setOf("fields", "include_deleted", "updated_since"),
            withWatermark.substringAfter("?").split("&").map { it.substringBefore("=") }.toSet(),
        )
    }

    @Test
    fun `a full sync does not ask for tombstones and an incremental one does`() {
        assertTrue(
            "A first sync has no cache to delete from, so deleted rows are pure payload.",
            "include_deleted=false" in bitcoinMapUrl(updatedSince = null, includeDeleted = false),
        )
        assertTrue(
            "An incremental sync must learn about removals, or a closed shop is drawn " +
                "forever — nothing else in the response says it is gone.",
            "include_deleted=true" in bitcoinMapUrl(updatedSince = "x", includeDeleted = true),
        )
    }

    @Test
    fun `a response decodes into places`() {
        val json = """
            [
              {"id": 1, "lat": 47.37, "lon": 8.54, "name": "Café Satoshi",
               "icon": "local_cafe", "address": "Bahnhofstrasse 1",
               "website": "https://example.com", "opening_hours": "Mo-Fr 08:00-18:00",
               "updated_at": "2026-09-01T10:00:00Z"},
              {"id": 2, "lat": null, "lon": null, "name": "No position"}
            ]
        """.trimIndent()

        val parsed = parsePlaces(json)
        assertEquals(2, parsed.size)

        val first = parsed.first()
        assertEquals("Café Satoshi", first.name)
        assertEquals("Mo-Fr 08:00-18:00", first.openingHours)
        assertEquals("2026-09-01T10:00:00Z", first.updatedAt)
        assertTrue(first.hasPosition)

        assertFalse(
            "A place with no position cannot be drawn or sorted, and iOS skips it too.",
            parsed[1].hasPosition,
        )
        assertNull(parsed[1].website)
    }

    @Test
    fun `the cache round-trips`() {
        val original = listOf(place(1), place(2, name = null))
        assertEquals(original, parsePlaces(encodePlaces(original)))
    }

    @Test
    fun `a sync updates, adds and removes`() {
        val cached = listOf(place(1, name = "Old name"), place(2), place(3))
        val synced = listOf(
            place(1, name = "New name", updatedAt = "2026-09-02T00:00:00Z"),
            place(4, updatedAt = "2026-09-03T00:00:00Z"),
            place(2, deletedAt = "2026-09-01T00:00:00Z"),
        )

        val merged = applySyncedPlaces(synced = synced, cached = cached)

        assertEquals(setOf(1, 3, 4), merged.map { it.id }.toSet())
        assertEquals("New name", merged.first { it.id == 1 }.name)
    }

    @Test
    fun `the watermark is the newest timestamp in the response`() {
        val synced = listOf(
            place(1, updatedAt = "2026-09-01T00:00:00Z"),
            place(2, updatedAt = "2026-09-03T00:00:00Z"),
            place(3, updatedAt = null),
        )
        assertEquals("2026-09-03T00:00:00Z", newestUpdatedAt(synced))

        assertNull(
            "A response with no timestamps must not advance the watermark — the next " +
                "sync would skip everything that changed in between.",
            newestUpdatedAt(listOf(place(1))),
        )
    }

    @Test
    fun `visible places are the nearest within the radius, in order`() {
        val zurich = place(1, lat = 47.3769, lon = 8.5417, name = "Zürich")
        val bern = place(2, lat = 46.9480, lon = 7.4474, name = "Bern")
        val lisbon = place(3, lat = 38.7223, lon = -9.1393, name = "Lisbon")
        val nowhere = place(4, lat = null, lon = null, name = "Nowhere")

        val visible = listOf(lisbon, bern, zurich, nowhere)
            .nearby(centerLat = 47.0, centerLon = 8.0, radiusKm = 200.0)

        assertEquals(
            "Nearest first, and the one 2,000 km away is out of range.",
            listOf("Bern", "Zürich"),
            visible.map { it.name },
        )
    }

    @Test
    fun `the visible set is capped`() {
        val many = (1..500).map { place(it, lat = 46.8 + it * 1e-5, lon = 8.2) }
        assertEquals(
            "A zoomed-out region matches thousands of places; drawing them all freezes " +
                "the screen (MapVCLocations.swift:108-113).",
            MAX_VISIBLE_PLACES,
            many.nearby(centerLat = 46.8, centerLon = 8.2, radiusKm = 1000.0).size,
        )
    }

    @Test
    fun `the default region covers enough of Switzerland to populate the list`() {
        val region = MapRegion.SWITZERLAND
        assertEquals(
            "3.8 degrees of latitude, as showDefaultSwitzerlandRegion sets.",
            3.8 * MapRegion.KM_PER_DEGREE,
            region.radiusKm,
            0.001,
        )
        assertTrue(
            "The flow asserts map.placeName with no location fix, so the fallback " +
                "region has to be wide enough to match places.",
            region.radiusKm > 100,
        )
    }

    @Test
    fun `no places is only shown once the sync has stopped`() {
        val syncing = MapUiState(isSyncing = true)
        assertFalse(
            "An empty list mid-sync means \"not yet\", not \"none here\".",
            syncing.showsNoPlaces,
        )
        assertTrue(syncing.copy(isSyncing = false).showsNoPlaces)
    }

    @Test
    fun `moving the map re-filters against the new centre`() {
        val zurich = place(1, lat = 47.3769, lon = 8.5417, name = "Zürich")
        val lisbon = place(2, lat = 38.7223, lon = -9.1393, name = "Lisbon")

        val atZurich = MapUiState(
            region = MapRegion(47.3769, 8.5417, 0.2),
            allPlaces = listOf(zurich, lisbon),
        ).withPlacesForRegion()
        assertEquals(listOf("Zürich"), atZurich.visiblePlaces.map { it.name })

        val atLisbon = atZurich
            .copy(region = MapRegion(38.7223, -9.1393, 0.2))
            .withPlacesForRegion()
        assertEquals(listOf("Lisbon"), atLisbon.visiblePlaces.map { it.name })
    }

    @Test
    fun `the website shown is stripped but the one opened is not`() {
        assertEquals("example.com", displayWebsite("https://www.example.com/"))
        assertEquals("example.com", displayWebsite("http://example.com"))
        assertEquals("shop.example.com/menu", displayWebsite("https://shop.example.com/menu"))
    }

    @Test
    fun `an unknown category still reads as something`() {
        assertEquals("Café", categoryDescription("local_cafe"))
        assertEquals("Bitcoin ATM", categoryDescription("local_atm"))
        assertEquals(
            "A category BTCMap adds later must not surface as a raw slug.",
            "Business",
            categoryDescription("wingsuit_rental"),
        )
        assertEquals("Business", categoryDescription(null))
    }
}
