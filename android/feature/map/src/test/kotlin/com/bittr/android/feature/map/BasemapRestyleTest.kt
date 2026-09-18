package com.bittr.android.feature.map

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The restyle's classification, against layers of OpenFreeMap's Liberty style as served
 * on 2026-09-18 (id, type, source layer). Only the renderer can show the result; this
 * holds which bucket each kind of layer falls in, including the ones the review named.
 */
class BasemapRestyleTest {

    private fun treat(id: String, type: String, sourceLayer: String? = null) =
        basemapTreatment(id, type, sourceLayer)

    @Test
    fun `ground, water and green`() {
        assertEquals(LayerTreatment.LAND, treat("background", "background"))
        assertEquals(LayerTreatment.REMOVE, treat("natural_earth", "raster"))
        assertEquals(LayerTreatment.WATER, treat("water", "fill", "water"))
        assertEquals(LayerTreatment.WATER_LINE, treat("waterway_river", "line", "waterway"))
        assertEquals(LayerTreatment.GREEN, treat("park", "fill", "park"))
        assertEquals(LayerTreatment.REMOVE, treat("park_outline", "line", "park"))
        assertEquals(LayerTreatment.GREEN, treat("landuse_residential", "fill", "landuse"))
        assertEquals(LayerTreatment.GREEN, treat("landcover_wood", "fill", "landcover"))
    }

    @Test
    fun `road casings go and fills turn white, motorways stay tinted`() {
        assertEquals(LayerTreatment.REMOVE, treat("road_minor_casing", "line", "transportation"))
        assertEquals(LayerTreatment.REMOVE, treat("bridge_motorway_casing", "line", "transportation"))
        assertEquals(LayerTreatment.REMOVE, treat("tunnel_street_casing", "line", "transportation"))
        assertEquals(LayerTreatment.ROAD, treat("road_minor", "line", "transportation"))
        assertEquals(LayerTreatment.ROAD, treat("bridge_trunk_primary", "line", "transportation"))
        assertEquals(LayerTreatment.MOTORWAY, treat("road_motorway", "line", "transportation"))
        assertEquals(LayerTreatment.MOTORWAY, treat("road_motorway_link", "line", "transportation"))
        assertEquals(LayerTreatment.KEEP, treat("road_major_rail", "line", "transportation"))
        assertEquals(LayerTreatment.REMOVE, treat("road_area_pattern", "fill", "transportation"))
        assertEquals(LayerTreatment.ROAD, treat("aeroway_runway", "line", "aeroway"))
    }

    @Test
    fun `buildings flatten`() {
        assertEquals(LayerTreatment.BUILDING, treat("building", "fill", "building"))
        assertEquals(LayerTreatment.REMOVE, treat("building-3d", "fill-extrusion", "building"))
    }

    @Test
    fun `labels - POI and transit hidden, roads later, places in warm ink`() {
        assertEquals(LayerTreatment.REMOVE, treat("poi_r1", "symbol", "poi"))
        assertEquals(LayerTreatment.REMOVE, treat("poi_transit", "symbol", "poi"))
        assertEquals(LayerTreatment.REMOVE, treat("airport", "symbol", "aerodrome_label"))
        assertEquals(LayerTreatment.ROAD_LABEL, treat("highway-name-major", "symbol", "transportation_name"))
        assertEquals(LayerTreatment.ROAD_LABEL, treat("highway-shield-non-us", "symbol", "transportation_name"))
        assertEquals(LayerTreatment.PLACE_LABEL, treat("label_town", "symbol", "place"))
        assertEquals(LayerTreatment.PLACE_LABEL, treat("label_country_1", "symbol", "place"))
    }

    @Test
    fun `anything unrecognised is left as OpenFreeMap drew it`() {
        assertEquals(LayerTreatment.KEEP, treat("boundary_2", "line", "boundary"))
        assertEquals(LayerTreatment.KEEP, treat("water_name_point_label", "symbol", "water_name"))
        assertEquals(LayerTreatment.KEEP, treat("something_new", "line", "a_future_layer"))
    }

    @Test
    fun `place categories map to the four row glyphs`() {
        assertEquals(PlaceGlyph.FOOD, placeGlyph("local_cafe"))
        assertEquals(PlaceGlyph.LODGING, placeGlyph("hotel"))
        assertEquals(PlaceGlyph.SHOP, placeGlyph("storefront"))
        assertEquals(PlaceGlyph.DEFAULT, placeGlyph("local_atm"))
        assertEquals(PlaceGlyph.DEFAULT, placeGlyph(null))
    }
}
