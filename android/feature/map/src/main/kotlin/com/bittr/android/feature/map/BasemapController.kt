package com.bittr.android.feature.map

import android.content.Context
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.Point

/**
 * Drives the MapLibre `MapView`: the camera, the place markers, and the view's own
 * lifecycle.
 *
 * Kept out of the composable because `MapView` is stateful in a way Compose is not —
 * it must be started and destroyed explicitly, the map arrives asynchronously
 * through `getMapAsync`, and camera and layer calls before that has happened are
 * dropped. Holding those three facts in one class is what keeps [MapScreen] readable.
 *
 * **Places are drawn as a data layer, not as marker views.** A `GeoJsonSource`
 * behind a `CircleLayer` redraws a few hundred points without allocating a view
 * each, and needs no icon asset — the iOS marker is a system glyph that has no
 * Android equivalent to port.
 */
internal class BasemapController(context: Context) {

    init {
        // Idempotent, and required before a MapView is constructed. No API key: the
        // key argument is for vendor-hosted tiles, which this app deliberately does
        // not use — see [MapBasemap].
        MapLibre.getInstance(context)
    }

    val view: MapView = MapView(context)

    var onRegionChanged: ((MapRegion) -> Unit)? = null

    private var map: MapLibreMap? = null
    private var pendingRegion: MapRegion? = null
    private var pendingPlaces: List<BitcoinPlace> = emptyList()

    /**
     * True while the camera is being moved by the app rather than by a finger.
     *
     * iOS carries the same flag (`isProgrammaticallyMovingMap`,
     * `MapVCLocations.swift:77-81`) and for the same reason: recentring fires the
     * idle callback, which would re-filter and then report a region the app just
     * set, in a loop.
     */
    private var movingProgrammatically = false

    fun start() {
        view.onCreate(null)
        view.onStart()
        view.onResume()
        view.getMapAsync { ready ->
            map = ready
            ready.setStyle(styleBuilder()) { style ->
                style.addSource(GeoJsonSource(PLACES_SOURCE))
                style.addLayer(
                    CircleLayer(PLACES_LAYER, PLACES_SOURCE).withProperties(
                        PropertyFactory.circleRadius(6f),
                        PropertyFactory.circleColor(MARKER_COLOR),
                        PropertyFactory.circleStrokeWidth(2f),
                        PropertyFactory.circleStrokeColor(MARKER_STROKE_COLOR),
                    ),
                )
                pendingRegion?.let { centre(it) }
                show(pendingPlaces)
            }
            ready.addOnCameraIdleListener {
                if (movingProgrammatically) {
                    movingProgrammatically = false
                    return@addOnCameraIdleListener
                }
                onRegionChanged?.invoke(ready.currentRegion())
            }
        }
    }

    fun destroy() {
        view.onPause()
        view.onStop()
        view.onDestroy()
        map = null
    }

    /** Moves the camera. Held until the map exists if it does not yet. */
    fun centre(region: MapRegion) {
        val ready = map
        if (ready == null) {
            pendingRegion = region
            return
        }
        // Only move for a region the camera is not already showing. Without this,
        // the state → camera → idle → state round trip never settles.
        if (ready.currentRegion().isSameAs(region)) return

        movingProgrammatically = true
        ready.animateCamera(
            CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder()
                    .target(LatLng(region.centerLat, region.centerLon))
                    .zoom(region.zoom())
                    .build(),
            ),
        )
    }

    /** Replaces the drawn places. */
    fun show(places: List<BitcoinPlace>) {
        pendingPlaces = places
        val source = map?.style?.getSourceAs<GeoJsonSource>(PLACES_SOURCE) ?: return
        source.setGeoJson(
            FeatureCollection.fromFeatures(
                places.filter { it.hasPosition }.map { place ->
                    Feature.fromGeometry(Point.fromLngLat(place.lon!!, place.lat!!))
                },
            ),
        )
    }

    private fun styleBuilder(): Style.Builder {
        val uri = MapBasemap.STYLE_URI
        return if (uri != null) {
            Style.Builder().fromUri(uri)
        } else {
            Style.Builder().fromJson(MapBasemap.offlineStyleJson())
        }
    }

    private companion object {
        const val PLACES_SOURCE = "bittr-places"
        const val PLACES_LAYER = "bittr-places-circles"

        /** The brand yellow iOS tints its markers with (`MapVCLocations.swift:213`). */
        const val MARKER_COLOR = "#F6C744"
        const val MARKER_STROKE_COLOR = "#1A1A1A"
    }
}

/**
 * What the camera is showing, in [MapRegion] terms.
 *
 * The renderer reports the area as two corners; the span is the difference between
 * them, which is the number iOS reads directly off `MKCoordinateRegion`.
 */
private fun MapLibreMap.currentRegion(): MapRegion {
    val bounds = projection.visibleRegion.latLngBounds
    val target = cameraPosition.target
    return MapRegion(
        centerLat = target?.latitude ?: MapRegion.SWITZERLAND.centerLat,
        centerLon = target?.longitude ?: MapRegion.SWITZERLAND.centerLon,
        spanDegrees = kotlin.math.abs(bounds.latitudeNorth - bounds.latitudeSouth),
    )
}

/**
 * Whether two regions are near enough to be the same one.
 *
 * The tolerances are a hair under what a user can perceive and well over the float
 * noise a camera round trip introduces — without them, the camera and the state
 * chase each other by fractions of a degree forever.
 */
private fun MapRegion.isSameAs(other: MapRegion): Boolean =
    kotlin.math.abs(centerLat - other.centerLat) < 1e-4 &&
        kotlin.math.abs(centerLon - other.centerLon) < 1e-4 &&
        kotlin.math.abs(spanDegrees - other.spanDegrees) < spanDegrees * 0.1

/**
 * The zoom level that shows [MapRegion.spanDegrees] of the world vertically.
 *
 * Web-Mercator tiles halve the visible span per zoom step, so this is the inverse of
 * that: at zoom 0 the whole 180° of latitude is on screen in one tile's height, and
 * every step up halves it. Approximate near the poles — irrelevant for a map of
 * where you can buy a coffee.
 */
private fun MapRegion.zoom(): Double {
    val span = spanDegrees.coerceAtLeast(1e-4)
    return (kotlin.math.ln(180.0 / span) / kotlin.math.ln(2.0)).coerceIn(1.0, 18.0)
}
