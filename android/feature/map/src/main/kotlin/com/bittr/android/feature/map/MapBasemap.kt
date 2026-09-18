package com.bittr.android.feature.map

/**
 * Where the basemap comes from — **the one configuration point for the tile host**.
 *
 * `android/docs/map-sdk-decision.md` decided the renderer (MapLibre, enforced by
 * `MapSdkGuardTest`) and, on 2026-09-11, that bittr would serve its own tiles. That host
 * (`tiles.getbittr.com`, BIT-139) never got its cloud account, storage or DNS, so the map
 * shipped blank. **On 2026-09-18 Ruben chose OpenFreeMap in its place** — decision 40 in
 * `shared/docs/android-port-decisions.md`:
 *
 * - no API key, no account and no cookies, so no identifier travels with a tile request;
 * - its privacy policy keeps no IP addresses by default, and at most 30 days when an
 *   incident needs them — close to what `tile-pipeline.md` §4 asked of bittr's own host;
 * - MapLibre only, so no SDK vendor telemetry (Google's map SDK was the alternative);
 * - free, with no SLA: it can go away without notice, which is the price of the above.
 *
 * It still sees the viewport and the client IP on every pan — any tile host does — and it
 * may sit behind Cloudflare. The shipped copy already says so without naming anyone
 * ("whoever serves them sees the area you are looking at"), so no copy changes.
 *
 * Moving to bittr's own tiles later is this one constant again; the pipeline in
 * `android/tools/tile-pipeline/` still builds the archive for it. The credit for these
 * tiles is [MapCopy.BASEMAP_ATTRIBUTION], rendered by `MapScreen`, and
 * `BasemapAttributionGuardTest` keeps the two together.
 */
internal object MapBasemap {

    /**
     * OpenFreeMap's "Liberty" style. A style document, not an archive: MapLibre is handed
     * the style, and the style names the tiles, glyphs and sprite — all on the same host,
     * which `TileHostGuardTest` checks. Null would fall back to [offlineStyleJson].
     */
    val STYLE_URI: String? = "https://tiles.openfreemap.org/styles/liberty"

    /**
     * A valid MapLibre style with no sources. The renderer paints the background and
     * nothing else; layers the app adds at runtime — the place pins — compose on top
     * exactly as they would over a basemap. It has no glyphs, so cluster counts do not
     * draw on it; the clusters themselves do.
     */
    fun offlineStyleJson(): String =
        """
        {
          "version": 8,
          "name": "bittr-offline",
          "sources": {},
          "layers": [
            {
              "id": "background",
              "type": "background",
              "paint": { "background-color": "${BasemapPalette.LAND}" }
            }
          ]
        }
        """.trimIndent()
}

/**
 * The basemap's colours — **the one place map style colours are written** (design review
 * pass 3: "warm quiet ground").
 *
 * Liberty is restyled at runtime rather than forked ([basemapTreatment]), so these are
 * MapLibre style values (hex strings handed to `setProperties`), not Compose colours.
 * They are not `Color.kt` tokens for the reason that file gives tokens at all: a token
 * has a dark counterpart and is measured against the canvas. The basemap has neither —
 * it is a fixed light surface in both schemes, like the Value screen's chart card,
 * because a dark basemap is a different style rather than a recolour. Anything drawn
 * *over* the map (markers, the locate button) takes theme tokens. `LiteralColourGuardTest`
 * scans for `Color(0x…)`, and nothing here is one.
 */
internal object BasemapPalette {
    /** Land and the background layer. Also the offline style's only colour. */
    const val LAND = "#F6F1E3"
    const val WATER = "#CBD9DE"

    /** Parks, landcover and landuse, in one flat colour — the review's "quiet". */
    const val GREEN = "#E9E7D4"
    const val ROAD = "#FFFFFF"
    const val MOTORWAY = "#E2DCC8"
    const val BUILDING = "#EDE7D6"

    /** Town and city names, the review's warm ink, on a halo of [LAND]. */
    const val PLACE_LABEL = "#3A342A"
}
