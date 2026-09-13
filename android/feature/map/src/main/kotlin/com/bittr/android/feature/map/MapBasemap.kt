package com.bittr.android.feature.map

/**
 * Where the basemap comes from — **the one configuration point for the tile host**.
 *
 * `android/docs/map-sdk-decision.md` decided two axes. The renderer is MapLibre and
 * is enforced by `MapSdkGuardTest`. The tile host is *bittr's own*, and the pipeline
 * that would serve those tiles is BIT-73 and does not exist yet. The decision is
 * explicit about what that means for this screen in the meantime:
 *
 * > no map screen should be pointed at a vendor's tiles while that sentence is in
 * > the app
 *
 * So [STYLE_URI] is null until BIT-73 ships, and the map renders [offlineStyleJson]:
 * a style with no sources and one background layer. Consequences, stated plainly
 * because a blank basemap looks like a bug:
 *
 * - **No tile request leaves the device.** The strongest form of the approved
 *   claim, by construction rather than by policy.
 * - **The screen works.** Everything `bitcoin_map.yaml` drives — the places list,
 *   opening a place, its website, the BTCMap credit, recentring — is the app's own
 *   code over its own data. Only the drawn streets are missing, and the places
 *   themselves are still drawn, positioned, and pan with the camera.
 * - **One constant changes when BIT-73 lands.** Set [STYLE_URI] and this file is the
 *   whole diff, which is what the decision meant by keeping the style URL a single
 *   configuration point.
 *
 * Do not fill this in with a vendor's style URL to "see the map while developing" —
 * that is the exact change the decision forbids, it names a provider the shipped
 * copy was written to avoid naming, and `MapSdkGuardTest` will not catch it because
 * a style URL is not a Gradle coordinate.
 */
internal object MapBasemap {

    /** Set by BIT-73, to a host bittr operates. Null means [offlineStyleJson]. */
    val STYLE_URI: String? = null

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
