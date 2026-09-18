package com.bittr.android.feature.map

import com.bittr.android.core.designsystem.normalizeSvgPath
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.core.graphics.PathParser
import androidx.core.view.doOnLayout
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdate
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapLibreMapOptions
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.BackgroundLayer
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.FillExtrusionLayer
import org.maplibre.android.style.layers.FillLayer
import org.maplibre.android.style.layers.Layer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.layers.RasterLayer
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.sources.GeoJsonOptions
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.Point

/**
 * The colours of what the app draws over the basemap, resolved from theme tokens by
 * the composable (the controller has no theme). ARGB ints, as MapLibre and
 * `android.graphics` take them.
 */
internal data class MarkerColors(val fill: Int, val stroke: Int, val ink: Int)

/**
 * Drives the MapLibre `MapView`: the camera, the place markers, the restyle, and the
 * view's own lifecycle.
 *
 * Kept out of the composable because `MapView` is stateful in a way Compose is not —
 * it must be started and destroyed explicitly, the map arrives asynchronously
 * through `getMapAsync`, and camera and layer calls before the style has loaded are
 * dropped. Everything that arrives early is held and applied in the style callback.
 *
 * **Places are a clustered symbol layer, not marker views.** A `GeoJsonSource` behind
 * two layers redraws a few hundred points without allocating a view each, and the
 * renderer does the clustering the review asked for below zoom 9.
 */
internal class BasemapController(context: Context, private val colors: MarkerColors) {

    init {
        // Idempotent, and required before a MapView is constructed. No API key: the
        // key argument is for vendor-hosted tiles, which this app deliberately does
        // not use — see [MapBasemap].
        MapLibre.getInstance(context)
    }

    /**
     * Texture mode, so the view draws inside Compose's layer: a `SurfaceView` punches
     * through it, which ignored the card's rounded clip (review pass 3, "map frame").
     */
    val view: MapView = MapView(
        context,
        MapLibreMapOptions.createFromAttributes(context).textureMode(true),
    )

    var onRegionChanged: ((MapRegion) -> Unit)? = null
    var onPlaceTapped: ((Int) -> Unit)? = null

    private val density = context.resources.displayMetrics.density
    private var map: MapLibreMap? = null
    private var styleLoaded = false
    private var pendingCamera: CameraMove? = null
    private var appliedSerial = -1
    private var pendingPlaces: List<BitcoinPlace> = emptyList()

    /**
     * Whether the move now under way should be reported back as a new region.
     *
     * A finger's, yes; the app's own framing, no. iOS draws the same line with
     * `isProgrammaticallyMovingMap` (`MapVCLocations.swift:77-81`). Taken from the
     * renderer's move reason rather than a flag set before each animation, because an
     * animation to where the camera already is never goes idle and would leave such a
     * flag set, swallowing the next real pan.
     */
    private var reportNextIdle = false

    /** Set just before a move the user asked for with a tap (a pin, a cluster). */
    private var tapMoveStarting = false

    fun start() {
        view.onCreate(null)
        view.onStart()
        view.onResume()
        view.getMapAsync { ready ->
            map = ready
            ready.uiSettings.isRotateGesturesEnabled = false
            ready.uiSettings.isTiltGesturesEnabled = false
            ready.setStyle(styleBuilder()) { style ->
                restyle(style)
                addPlaceLayers(style)
                styleLoaded = true
                show(pendingPlaces)
                pendingCamera?.let { move(it) }

                // Registered only now: before the style loads the camera sits at
                // MapLibre's 0,0 default, and an idle reported from there would filter
                // the list around the Gulf of Guinea.
                ready.addOnCameraMoveStartedListener { reason ->
                    reportNextIdle = tapMoveStarting ||
                        reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE
                    tapMoveStarting = false
                }
                ready.addOnCameraIdleListener {
                    if (!reportNextIdle) return@addOnCameraIdleListener
                    reportNextIdle = false
                    onRegionChanged?.invoke(ready.currentRegion())
                }
                ready.addOnMapClickListener { point -> onTap(ready, point) }
            }
        }
    }

    fun destroy() {
        view.onPause()
        view.onStop()
        view.onDestroy()
        map = null
        styleLoaded = false
    }

    /** Applies a camera request once; held until the style and the view's size exist. */
    fun move(request: CameraMove) {
        pendingCamera = request
        val ready = map ?: return
        if (!styleLoaded || request.serial == appliedSerial) return
        // A fit is computed from the view's size, which is zero until the first layout.
        if (view.width == 0 || view.height == 0) {
            view.doOnLayout { pendingCamera?.let { move(it) } }
            return
        }
        val update = cameraUpdate(ready, request.target) ?: return
        // The first framing jumps: animating from MapLibre's whole-world default is a
        // swoop across the planet on every open.
        if (appliedSerial < 0) ready.moveCamera(update) else ready.animateCamera(update)
        appliedSerial = request.serial
    }

    /** Replaces the drawn places. */
    fun show(places: List<BitcoinPlace>) {
        pendingPlaces = places
        if (!styleLoaded) return
        val source = map?.style?.getSourceAs<GeoJsonSource>(PLACES_SOURCE) ?: return
        source.setGeoJson(
            FeatureCollection.fromFeatures(
                places.filter { it.hasPosition }.map { place ->
                    Feature.fromGeometry(Point.fromLngLat(place.lon!!, place.lat!!)).apply {
                        addNumberProperty(PLACE_ID, place.id)
                    }
                },
            ),
        )
    }

    private fun cameraUpdate(ready: MapLibreMap, target: CameraTarget): CameraUpdate? =
        when (target) {
            is CameraTarget.Centre -> CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder()
                    .target(LatLng(target.lat, target.lon))
                    .zoom(target.zoom ?: ready.cameraPosition.zoom)
                    .build(),
            )
            is CameraTarget.Fit -> {
                val padding = (CameraTarget.FIT_PADDING_DP * density).toInt()
                val bounds = LatLngBounds.from(
                    target.bounds.north,
                    target.bounds.east,
                    target.bounds.south,
                    target.bounds.west,
                )
                ready.getCameraForLatLngBounds(bounds, intArrayOf(padding, padding, padding, padding))
                    ?.let { fitted ->
                        CameraUpdateFactory.newCameraPosition(
                            CameraPosition.Builder(fitted)
                                .zoom(fitted.zoom.coerceIn(CameraTarget.MIN_ZOOM, CameraTarget.MAX_ZOOM))
                                .build(),
                        )
                    }
            }
        }

    /**
     * A tap on a pin opens its sheet and centres it; a tap on a cluster zooms to where
     * it splits. Anything else falls through to the map's own handling.
     */
    private fun onTap(ready: MapLibreMap, point: LatLng): Boolean {
        val screen = ready.projection.toScreenLocation(point)
        val slop = TAP_SLOP_DP * density
        val box = RectF(screen.x - slop, screen.y - slop, screen.x + slop, screen.y + slop)
        val feature = ready.queryRenderedFeatures(box, PIN_LAYER, CLUSTER_LAYER).firstOrNull()
            ?: return false
        val position = (feature.geometry() as? Point) ?: return false

        if (feature.hasProperty(POINT_COUNT)) {
            val source = ready.style?.getSourceAs<GeoJsonSource>(PLACES_SOURCE) ?: return false
            val zoom = source.getClusterExpansionZoom(feature).toDouble()
            tapMoveStarting = true
            ready.animateCamera(
                CameraUpdateFactory.newLatLngZoom(LatLng(position.latitude(), position.longitude()), zoom),
            )
            return true
        }

        val id = feature.getNumberProperty(PLACE_ID)?.toInt() ?: return false
        tapMoveStarting = true
        ready.animateCamera(
            CameraUpdateFactory.newLatLng(LatLng(position.latitude(), position.longitude())),
        )
        onPlaceTapped?.invoke(id)
        return true
    }

    /**
     * Applies [basemapTreatment] to every layer the loaded style has. On the offline
     * style that is the background alone.
     */
    private fun restyle(style: Style) {
        style.layers.toList().forEach { layer ->
            val treatment = basemapTreatment(layer.id, layer.styleType(), layer.sourceLayerOrNull())
            when (treatment) {
                LayerTreatment.REMOVE -> style.removeLayer(layer)
                LayerTreatment.LAND -> layer.setProperties(PropertyFactory.backgroundColor(BasemapPalette.LAND))
                LayerTreatment.WATER -> layer.setProperties(
                    PropertyFactory.fillColor(BasemapPalette.WATER),
                    PropertyFactory.fillOutlineColor(BasemapPalette.WATER),
                )
                LayerTreatment.WATER_LINE -> layer.setProperties(PropertyFactory.lineColor(BasemapPalette.WATER))
                LayerTreatment.GREEN -> if (layer is FillLayer && !layer.fillPattern.isNull) {
                    // A sprite pattern (wetland) wins over any fill colour.
                    style.removeLayer(layer)
                } else {
                    layer.setProperties(
                        PropertyFactory.fillColor(BasemapPalette.GREEN),
                        PropertyFactory.fillOutlineColor(BasemapPalette.GREEN),
                        PropertyFactory.fillOpacity(1f),
                    )
                }
                LayerTreatment.ROAD -> layer.setProperties(
                    PropertyFactory.lineColor(BasemapPalette.ROAD),
                    PropertyFactory.lineWidth(roadWidth()),
                )
                LayerTreatment.MOTORWAY -> layer.setProperties(
                    PropertyFactory.lineColor(BasemapPalette.MOTORWAY),
                    PropertyFactory.lineWidth(roadWidth()),
                )
                LayerTreatment.BUILDING -> layer.setProperties(
                    PropertyFactory.fillColor(BasemapPalette.BUILDING),
                    PropertyFactory.fillOutlineColor(BasemapPalette.BUILDING),
                )
                LayerTreatment.ROAD_LABEL -> layer.minZoom = maxOf(layer.minZoom, ROAD_LABEL_MIN_ZOOM)
                LayerTreatment.PLACE_LABEL -> layer.setProperties(
                    PropertyFactory.textColor(BasemapPalette.PLACE_LABEL),
                    PropertyFactory.textHaloColor(BasemapPalette.LAND),
                )
                LayerTreatment.KEEP -> Unit
            }
        }
    }

    private fun addPlaceLayers(style: Style) {
        style.addImage(PIN_IMAGE, pinBitmap())
        style.addSource(
            GeoJsonSource(
                PLACES_SOURCE,
                GeoJsonOptions()
                    .withCluster(true)
                    // Clusters exist up to zoom 8; from 9 every place is its own pin.
                    .withClusterMaxZoom(CLUSTER_MAX_ZOOM)
                    .withClusterRadius(CLUSTER_RADIUS),
            ),
        )
        style.addLayer(
            CircleLayer(CLUSTER_LAYER, PLACES_SOURCE)
                .withFilter(Expression.has(POINT_COUNT))
                .withProperties(
                    PropertyFactory.circleRadius(CLUSTER_DIAMETER_DP / 2),
                    PropertyFactory.circleColor(colors.fill),
                    PropertyFactory.circleStrokeWidth(STROKE_DP),
                    PropertyFactory.circleStrokeColor(colors.stroke),
                ),
        )
        style.addLayer(
            SymbolLayer(CLUSTER_COUNT_LAYER, PLACES_SOURCE)
                .withFilter(Expression.has(POINT_COUNT))
                .withProperties(
                    PropertyFactory.textField(Expression.toString(Expression.get(POINT_COUNT))),
                    // A font OpenFreeMap's glyph host serves; Liberty uses it for country names.
                    PropertyFactory.textFont(arrayOf("Noto Sans Bold")),
                    PropertyFactory.textSize(CLUSTER_TEXT_SP),
                    PropertyFactory.textColor(colors.ink),
                    PropertyFactory.textAllowOverlap(true),
                    PropertyFactory.textIgnorePlacement(true),
                ),
        )
        style.addLayer(
            SymbolLayer(PIN_LAYER, PLACES_SOURCE)
                .withFilter(Expression.not(Expression.has(POINT_COUNT)))
                .withProperties(
                    PropertyFactory.iconImage(PIN_IMAGE),
                    PropertyFactory.iconAnchor(Property.ICON_ANCHOR_BOTTOM),
                    // The bitmap carries a shadow margin under the circle; this puts
                    // the circle's own bottom edge, not the margin's, on the place.
                    PropertyFactory.iconOffset(arrayOf(0f, SHADOW_MARGIN_DP)),
                    PropertyFactory.iconAllowOverlap(true),
                    PropertyFactory.iconIgnorePlacement(true),
                ),
        )
    }

    /**
     * The pin: a [PIN_DIAMETER_DP] circle in the brand yellow with a white ring, the
     * bitcoin mark in ink, and a soft shadow. Drawn once per style load, at the screen's
     * density, so the renderer shows it at its dp size.
     */
    private fun pinBitmap(): Bitmap {
        val margin = SHADOW_MARGIN_DP * density
        val diameter = PIN_DIAMETER_DP * density
        val side = (diameter + 2 * margin).toInt()
        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        bitmap.density = view.resources.displayMetrics.densityDpi
        val canvas = Canvas(bitmap)
        val centre = side / 2f
        val radius = diameter / 2f

        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.fill
            // Ink at low alpha, derived from the ink token rather than written here.
            setShadowLayer(2f * density, 0f, 1f * density, (colors.ink and 0x00FFFFFF) or SHADOW_ALPHA)
        }
        canvas.drawCircle(centre, centre, radius - STROKE_DP * density / 2, fill)
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.stroke
            style = Paint.Style.STROKE
            strokeWidth = STROKE_DP * density
        }
        canvas.drawCircle(centre, centre, radius - STROKE_DP * density / 2, ring)

        val glyph = PathParser.createPathFromPathData(normalizeSvgPath(MapIconPaths.BITCOIN))
        val glyphSize = GLYPH_DP * density
        val scale = glyphSize / ICON_VIEWPORT
        canvas.save()
        canvas.translate(centre - glyphSize / 2, centre - glyphSize / 2)
        canvas.scale(scale, scale)
        canvas.drawPath(
            glyph,
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = colors.ink
                style = Paint.Style.STROKE
                strokeWidth = GLYPH_STROKE
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            },
        )
        canvas.restore()
        return bitmap
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
        const val PIN_LAYER = "bittr-places-pins"
        const val CLUSTER_LAYER = "bittr-places-clusters"
        const val CLUSTER_COUNT_LAYER = "bittr-places-cluster-counts"
        const val PIN_IMAGE = "bittr-pin"
        const val PLACE_ID = "id"

        /** Written by the renderer on every cluster feature. */
        const val POINT_COUNT = "point_count"

        const val PIN_DIAMETER_DP = 36f
        const val CLUSTER_DIAMETER_DP = 40f
        const val STROKE_DP = 2f
        const val GLYPH_DP = 18f
        const val SHADOW_MARGIN_DP = 3f
        const val CLUSTER_TEXT_SP = 14f
        const val CLUSTER_MAX_ZOOM = 8
        const val CLUSTER_RADIUS = 50
        const val TAP_SLOP_DP = 8f
        const val ICON_VIEWPORT = 24f
        const val GLYPH_STROKE = 2.4f

        /** 30 % alpha in the top byte. */
        const val SHADOW_ALPHA = 0x4D000000
    }
}

/** The review's "1–2 px" road fills: 1 at zoom 10, rising to 2 at street level. */
private fun roadWidth(): Expression =
    Expression.interpolate(
        Expression.linear(),
        Expression.zoom(),
        Expression.stop(10, 1f),
        Expression.stop(18, 2f),
    )

private fun Layer.styleType(): String = when (this) {
    is BackgroundLayer -> "background"
    is RasterLayer -> "raster"
    is FillExtrusionLayer -> "fill-extrusion"
    is FillLayer -> "fill"
    is LineLayer -> "line"
    is SymbolLayer -> "symbol"
    is CircleLayer -> "circle"
    else -> "other"
}

private fun Layer.sourceLayerOrNull(): String? = when (this) {
    is FillLayer -> sourceLayer
    is LineLayer -> sourceLayer
    is SymbolLayer -> sourceLayer
    is FillExtrusionLayer -> sourceLayer
    is CircleLayer -> sourceLayer
    else -> null
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
