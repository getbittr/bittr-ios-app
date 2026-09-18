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
     * The land/background colour. Deliberately a neutral wash rather than the brand
     * yellow: the place markers and the user dot have to stay legible on it, and the
     * canvas is already yellow behind the map card.
     */
    private const val BACKGROUND_COLOR = "#E8E4DC"

    /**
     * A valid MapLibre style with no sources. The renderer paints the background and
     * nothing else; layers the app adds at runtime — the places circles — compose on
     * top exactly as they would over a basemap.
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
              "paint": { "background-color": "$BACKGROUND_COLOR" }
            }
          ]
        }
        """.trimIndent()
}
