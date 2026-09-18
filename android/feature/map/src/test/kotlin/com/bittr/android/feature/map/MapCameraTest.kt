package com.bittr.android.feature.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The opening camera — the fix for review pass 3's "no markers". See [CameraMove] for
 * why the camera frames the list rather than deriving a zoom from the region.
 */
class MapCameraTest {

    private fun place(id: Int, lat: Double, lon: Double) = BitcoinPlace(
        id = id, lat = lat, lon = lon, icon = null, name = "P$id", address = null,
        updatedAt = null, deletedAt = null, website = null, openingHours = null,
    )

    /** The pass-3 fixture: a fix near Ramersberg, the places ~1 km east in Sarnen. */
    private val fix = MapRegion(46.8990, 8.2330, MapRegion.USER_SPAN_DEGREES)
    private val sarnen = listOf(place(1, 46.8960, 8.2460), place(2, 46.8990, 8.2470), place(3, 46.8975, 8.2455))

    @Test
    fun `with a fix the camera fits the listed places`() {
        val target = openingCamera(sarnen, fix, hasFix = true)
        assertEquals(CameraTarget.Fit(PlaceBounds(46.8960, 8.2455, 46.8990, 8.2470)), target)
    }

    @Test
    fun `without a fix it is a country-level view centred on the places`() {
        val target = openingCamera(sarnen, MapRegion.SWITZERLAND, hasFix = false)
        assertTrue(target is CameraTarget.Centre)
        target as CameraTarget.Centre
        assertEquals(CameraTarget.COUNTRY_ZOOM, target.zoom)
        assertEquals(46.8975, target.lat, 1e-9)
        assertEquals(8.24625, target.lon, 1e-9)
    }

    @Test
    fun `one place is centred at the zoom ceiling rather than fitted`() {
        val target = openingCamera(sarnen.take(1), fix, hasFix = true)
        assertEquals(CameraTarget.Centre(46.8960, 8.2460, CameraTarget.MAX_ZOOM), target)
    }

    @Test
    fun `no places centres the region`() {
        assertEquals(
            CameraTarget.Centre(fix.centerLat, fix.centerLon, CameraTarget.MAX_ZOOM),
            openingCamera(emptyList(), fix, hasFix = true),
        )
    }

    @Test
    fun `a sync after the user has panned does not move the camera`() {
        val panned = MapUiState(allPlaces = sarnen, region = fix, hasFix = true, userMoved = true)
        assertEquals(panned.camera, panned.withPlacesForRegion().framedIfUntouched().camera)

        val untouched = panned.copy(userMoved = false).withPlacesForRegion().framedIfUntouched()
        assertEquals(panned.camera.serial + 1, untouched.camera.serial)
    }

    @Test
    fun `asking twice for the same framing is still two requests`() {
        val once = MapUiState(allPlaces = sarnen, region = fix, hasFix = true).withPlacesForRegion().framed()
        val twice = once.framed()
        assertEquals(once.camera.target, twice.camera.target)
        assertTrue(twice.camera.serial > once.camera.serial)
    }
}
