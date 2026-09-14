package com.bittr.android.feature.map

/**
 * Where the basemap comes from — **the one configuration point for the tile host**.
 *
 * `android/docs/map-sdk-decision.md` decided two axes. The renderer is MapLibre and
 * is enforced by `MapSdkGuardTest`. The tile host is *bittr's own*, and what is
 * missing is narrower than "not built yet": `android/tools/tile-pipeline/` builds and
 * verifies the archive end to end, and a real one has been built and measured. What
 * does not exist is somewhere to put it — `tiles.getbittr.com` needs a cloud account,
 * object-storage credentials and DNS over `getbittr.com`, none of which exist inside
 * an agent container, and §2's question of *who terminates TLS* there is still open.
 * That is BIT-139, and until it answers there is no URL to paste here. The decision is
 * explicit about what that means for this screen in the meantime:
 *
 * > no map screen should be pointed at a vendor's tiles while that sentence is in
 * > the app
 *
 * So [STYLE_URI] is null until BIT-139 lands a host, and the map renders
 * [offlineStyleJson]: a style with no sources and one background layer. Consequences, stated plainly
 * because a blank basemap looks like a bug:
 *
 * - **No tile request leaves the device.** The strongest form of the approved
 *   claim, by construction rather than by policy.
 * - **The screen works.** Everything `bitcoin_map.yaml` drives — the places list,
 *   opening a place, its website, the BTCMap credit, recentring — is the app's own
 *   code over its own data. Only the drawn streets are missing, and the places
 *   themselves are still drawn, positioned, and pan with the camera.
 * - **One constant, but three files.** The style URL stays a single configuration
 *   point — that is what the decision meant, and it holds. It is not the same claim
 *   as "this file is the whole diff", which is the sentence that walks someone into a
 *   red build: setting [STYLE_URI] un-dormants `BasemapAttributionGuardTest`, which
 *   then also requires the basemap credit as a constant in `MapCopy.kt` and a
 *   reference to that constant in `MapScreen.kt`. BIT-119 done-when items 3 and 4.
 *
 * Do not fill this in with a vendor's style URL to "see the map while developing" —
 * that is the exact change the decision forbids, it names a provider the shipped
 * copy was written to avoid naming, and `MapSdkGuardTest` will not catch it because
 * a style URL is not a Gradle coordinate.
 */
internal object MapBasemap {

    /**
     * Set by BIT-119, to a host bittr operates. Null means [offlineStyleJson].
     *
     * **A style document, not the archive.** MapLibre is handed a style and the style
     * names the archive as one of its sources, so the value here is
     * `https://tiles.getbittr.com/basemap/<yyyy-mm>/style.json` — not the
     * `ch.pmtiles` sitting next to it, which is the plausible wrong paste because the
     * archive is the thing the pipeline spends hours building. The version in the
     * path is pinned deliberately: a refresh publishes a new folder, so it cannot
     * half-land over a running app.
     *
     * `android/tools/tile-pipeline/build-basemap.sh` prints the exact line to paste
     * as its last step — and note that it *rebuilds*, ~2h15m from cold, because the
     * archive is never checked in and so there is no file waiting to be uploaded.
     *
     * The credit must land **no later than** this constant, not necessarily in the
     * same commit: it may land earlier, because the guard only arms once this is a
     * URL. Landing it earlier is a judgement call, not a free win — while this is
     * null the app fetches no tiles, so the credit would name upstreams the app does
     * not use. The wording is settled and is transcription, not a decision; it is in
     * `android/docs/tile-pipeline.md` §3 under "The wording, settled", spelled with
     * escapes rather than pasted characters. `BasemapAttributionGuardTest` fails the
     * build if it is missing, naming both `MapCopy.kt` and `MapScreen.kt`.
     */
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
