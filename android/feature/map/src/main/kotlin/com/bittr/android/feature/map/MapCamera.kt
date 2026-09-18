package com.bittr.android.feature.map

/**
 * Where the app asks the camera to go, as opposed to where a finger took it.
 *
 * **Why this exists (design review pass 3, "no markers").** The camera used to follow
 * [MapRegion] directly, and a region's zoom was derived from its span with
 * `log2(180 / span)`. Two things were wrong with that pairing, and together they put
 * every marker off screen while the list under the map was full:
 *
 * - The list is every place within `span × 111 km` of the centre — a *radius* the size of
 *   the whole span, as on iOS (`MapVCLocations.swift:93`).
 * - The camera showed less than that span. MapLibre's zoom 0 is one 512 dp tile for the
 *   whole world, so a 280 dp card at `log2(180 / span)` shows about three quarters of the
 *   span top to bottom at Swiss latitudes — and the list reached a full span from the
 *   centre, ~2.7× past the card's top and bottom edges.
 *
 * With a location fix that is a list reaching 1.5 km out under a map ~1.1 km tall, and
 * the fixture places sat ~1 km east: drawn, just outside the card. Panning (the flow's `07_map_moved`) brought them in at
 * the right-hand edge, which is what gave it away. Nothing was wrong with the layer.
 *
 * So the camera no longer derives from the region. It frames the *places the list
 * shows* ([openingCamera]), on the events that change that list for a reason other than
 * the user moving the map — the cached set, the sync, the arrival fix, the my-location
 * button — and never in response to its own movement.
 *
 * @param serial increases on every request, so asking for the same target twice (the
 *   my-location button, tapped twice) still moves a camera the user has since panned.
 */
internal data class CameraMove(val serial: Int, val target: CameraTarget)

internal sealed interface CameraTarget {

    /** Fit these bounds with [FIT_PADDING_DP] on every side, zoom clamped to [MIN_ZOOM]..[MAX_ZOOM]. */
    data class Fit(val bounds: PlaceBounds) : CameraTarget

    /** Centre on a point. A null [zoom] keeps whatever zoom the camera already has. */
    data class Centre(val lat: Double, val lon: Double, val zoom: Double?) : CameraTarget

    companion object {
        const val FIT_PADDING_DP = 48f
        const val MIN_ZOOM = 5.0
        // 15, not 12: the places are often a few hundred metres apart, and at 12 their pins
        // stacked into what read as one (review S27, pass 4).
        const val MAX_ZOOM = 15.0

        /**
         * With no fix the list is the ~200 places nearest the middle of Switzerland, which
         * spreads across the country and past it. Fitting those would zoom out to a
         * continent; the review asked for a country-level view around them instead.
         */
        const val COUNTRY_ZOOM = 7.0
    }
}

/** The smallest box holding a set of places. */
internal data class PlaceBounds(
    val south: Double,
    val west: Double,
    val north: Double,
    val east: Double,
) {
    val centreLat: Double get() = (south + north) / 2
    val centreLon: Double get() = (west + east) / 2

    /**
     * One place, or several at one address (the flow's Sarnen fixture has two). A fit to
     * a zero-size box is undefined in the renderer, so these are centred at [CameraTarget.MAX_ZOOM].
     */
    val isPoint: Boolean get() = north - south < 1e-6 && east - west < 1e-6
}

internal fun List<BitcoinPlace>.bounds(): PlaceBounds? {
    val positioned = filter { it.hasPosition }
    if (positioned.isEmpty()) return null
    return PlaceBounds(
        south = positioned.minOf { it.lat!! },
        west = positioned.minOf { it.lon!! },
        north = positioned.maxOf { it.lat!! },
        east = positioned.maxOf { it.lon!! },
    )
}

/**
 * The camera for a freshly loaded list.
 *
 * - **With a fix:** fit the places. They are all within walking distance, so the fit is
 *   the answer to "where are they"; the clamp keeps one place from zooming to a doorway.
 * - **Without one:** a country-level view centred on them — see [CameraTarget.COUNTRY_ZOOM].
 * - **No places:** the region's own centre, at the same zoom the places would have got.
 */
internal fun openingCamera(
    places: List<BitcoinPlace>,
    region: MapRegion,
    hasFix: Boolean,
): CameraTarget {
    val bounds = places.bounds()
    return when {
        bounds == null -> CameraTarget.Centre(
            region.centerLat,
            region.centerLon,
            if (hasFix) CameraTarget.MAX_ZOOM else CameraTarget.COUNTRY_ZOOM,
        )
        !hasFix -> CameraTarget.Centre(bounds.centreLat, bounds.centreLon, CameraTarget.COUNTRY_ZOOM)
        bounds.isPoint -> CameraTarget.Centre(bounds.centreLat, bounds.centreLon, CameraTarget.MAX_ZOOM)
        else -> CameraTarget.Fit(bounds)
    }
}
