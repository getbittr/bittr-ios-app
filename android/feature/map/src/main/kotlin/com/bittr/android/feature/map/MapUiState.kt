package com.bittr.android.feature.map

/**
 * Where the map is pointed, in the terms the places filter needs: a centre and how
 * much of the world is on screen.
 *
 * iOS reads this straight off `MKCoordinateRegion` and turns the latitude span into
 * kilometres with the standard 111 km per degree (`MapVCLocations.swift:93`). The
 * renderer here reports the area it is showing as a pair of corners instead, so the
 * span is derived once, here, and the rest of the port is unchanged.
 */
internal data class MapRegion(
    val centerLat: Double,
    val centerLon: Double,
    val spanDegrees: Double,
) {

    /** iOS's `region.span.latitudeDelta * 111`. */
    val radiusKm: Double get() = spanDegrees * KM_PER_DEGREE

    internal companion object {

        const val KM_PER_DEGREE = 111.0

        /**
         * The fallback region, from `showDefaultSwitzerlandRegion`
         * (`MapVCLocations.swift:152-159`). It is what the map shows with no
         * position fix — denied permission, an emulator with nothing simulated — and
         * it is deliberately zoomed out far enough to put places in the list, which
         * is what lets `bitcoin_map.yaml` assert `map.placeName` without a location.
         */
        val SWITZERLAND = MapRegion(centerLat = 46.8182, centerLon = 8.2275, spanDegrees = 3.8)

        /** `latitudinalMeters: 1500` — the region iOS centres on the user with. */
        val USER_SPAN_DEGREES = 1.5 / KM_PER_DEGREE
    }
}

/**
 * State of the map screen.
 *
 * @param isSyncing drives `map.mapSpinner`. It stops when the BTCMap sync finishes,
 *   success or failure alike (`resyncBTCPlaces` stops it down both branches), which
 *   is what lets the flow wait on it disappearing rather than on places appearing.
 * @param visiblePlaces the nearest [MAX_VISIBLE_PLACES] to the centre, in order.
 *   Both the list and the markers read this, as on iOS where `currentPlaces` backs
 *   the table and the annotations.
 */
internal data class MapUiState(
    val region: MapRegion = MapRegion.SWITZERLAND,
    val allPlaces: List<BitcoinPlace> = emptyList(),
    val visiblePlaces: List<BitcoinPlace> = emptyList(),
    val isSyncing: Boolean = true,
    val openPlace: BitcoinPlace? = null,
    val openWebsite: String? = null,
    val alert: MapAlert? = null,
) {

    /**
     * `noPlacesLabel` is shown only once the sync has stopped
     * (`MapVCTable.swift:23-27`) — an empty list mid-sync is "not yet", not "none
     * here", and saying otherwise flashes the wrong message on every open.
     */
    val showsNoPlaces: Boolean get() = !isSyncing && visiblePlaces.isEmpty()

    /** Recomputes the visible set for the current region. */
    fun withPlacesForRegion(): MapUiState = copy(
        visiblePlaces = allPlaces.nearby(
            centerLat = region.centerLat,
            centerLon = region.centerLon,
            radiusKm = region.radiusKm,
        ),
    )
}

/** The two alerts this screen raises, as `showAlert` calls on iOS. */
internal data class MapAlert(val title: String, val message: String)
