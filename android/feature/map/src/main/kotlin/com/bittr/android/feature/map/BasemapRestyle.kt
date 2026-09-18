package com.bittr.android.feature.map

/**
 * What happens to one of Liberty's layers once the style has loaded.
 *
 * Design review pass 3 asked for a warm, quiet ground under the pins rather than
 * Liberty's greens, oranges and POI icons. It is done here, at runtime, rather than by
 * forking the style: a forked style is a file bittr would have to host, and hosting is
 * the thing decision 40 is standing in for. OpenFreeMap keeps serving its own style,
 * sprites and glyphs from the one approved host; the app only changes paint.
 *
 * Classified on the layer's **type and source layer**, with its id consulted only
 * where the OpenMapTiles schema cannot tell (a casing and a fill share a source layer).
 * The schema is stable across OpenFreeMap's style revisions in a way layer ids are not,
 * so a renamed layer still lands in the right bucket, and an unknown one is [KEEP] —
 * the style as OpenFreeMap drew it, never a hole in the map.
 */
internal enum class LayerTreatment {
    REMOVE,
    LAND,
    WATER,
    WATER_LINE,
    GREEN,
    ROAD,
    MOTORWAY,
    BUILDING,

    /** Road names and shields, from zoom [ROAD_LABEL_MIN_ZOOM]. */
    ROAD_LABEL,
    PLACE_LABEL,
    KEEP,
}

internal const val ROAD_LABEL_MIN_ZOOM = 13f

/**
 * @param type the MapLibre style type: `background`, `fill`, `line`, `symbol`, …
 * @param sourceLayer the OpenMapTiles source layer, or null for layers without one.
 */
internal fun basemapTreatment(id: String, type: String, sourceLayer: String?): LayerTreatment =
    when {
        type == "background" -> LayerTreatment.LAND
        // Natural Earth relief shading. Faded, but it tints the ground at country zoom,
        // which is exactly the zoom the map opens at without a fix.
        type == "raster" -> LayerTreatment.REMOVE
        // 3-D buildings from zoom 14: a flat fill is the quiet version, and it is there.
        type == "fill-extrusion" -> LayerTreatment.REMOVE

        sourceLayer == "water" && type == "fill" -> LayerTreatment.WATER
        sourceLayer == "waterway" && type == "line" -> LayerTreatment.WATER_LINE

        sourceLayer == "aeroway" && type == "line" -> LayerTreatment.ROAD
        sourceLayer in GREEN_LAYERS && type == "fill" -> LayerTreatment.GREEN
        // Park outlines are a dashed green edge around a colour that is now flat.
        sourceLayer in GREEN_LAYERS && type == "line" -> LayerTreatment.REMOVE

        sourceLayer == "transportation" && type == "line" -> when {
            "casing" in id -> LayerTreatment.REMOVE
            // Rail keeps Liberty's grey: it is already quiet, and a white rail line would
            // read as a road.
            "rail" in id -> LayerTreatment.KEEP
            "motorway" in id -> LayerTreatment.MOTORWAY
            else -> LayerTreatment.ROAD
        }
        // Pedestrian-area hatching: a sprite pattern, which a flat colour cannot override.
        sourceLayer == "transportation" && type == "fill" -> LayerTreatment.REMOVE

        sourceLayer == "building" && type == "fill" -> LayerTreatment.BUILDING

        // POI and transit labels — shops, stations, airports. The pins are the only
        // points of interest this map is for.
        sourceLayer in HIDDEN_LABEL_LAYERS -> LayerTreatment.REMOVE
        sourceLayer == "transportation_name" -> LayerTreatment.ROAD_LABEL
        sourceLayer == "place" && type == "symbol" -> LayerTreatment.PLACE_LABEL

        else -> LayerTreatment.KEEP
    }

private val GREEN_LAYERS = setOf("park", "landcover", "landuse", "aeroway")
private val HIDDEN_LABEL_LAYERS = setOf("poi", "aerodrome_label")
