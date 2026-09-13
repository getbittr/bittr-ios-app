package com.bittr.android

import com.bittr.android.SourceTree.code
import com.bittr.android.SourceTree.repoPath
import java.util.regex.Pattern
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Keeps a tile vendor out of the map's request path (BIT-73).
 *
 * [MapSdkGuardTest] holds the *renderer*. This holds the *host*, and they are
 * separate problems with separate failure modes. MapLibre is a client: it will
 * render happily from anyone's tiles, and swapping the host is editing one string,
 * not editing the dependency graph. So every check in that file can pass on a build
 * that fetches its basemap from MapTiler.
 *
 * [LocationEgressGuardTest] holds the third, adjacent rule — no coordinate in a
 * request *body* — and is explicit that tile requests themselves are allowed and
 * that it "must never be fixed by banning them". That is the hole this file fills:
 * the tile fetch is legitimate, so the only thing left to assert about it is *who
 * receives it*.
 *
 * Ruben chose on [BIT-53](/BIT/issues/BIT-53) that bittr serves its own tiles, over
 * the cheaper recommendation to keep a vendor. What that bought is narrow and worth
 * stating exactly: **the viewport and the client IP still go to whoever serves the
 * tiles on every pan** — that is what a tile request is — but with tiles bittr
 * serves, the party that learns it is bittr, and retention becomes bittr's decision.
 * A vendor host in this repo silently un-buys that. See
 * `android/docs/map-sdk-decision.md` and `android/docs/tile-pipeline.md`.
 *
 * ### Why the build has to be the tripwire
 *
 * Nothing else would catch it:
 *
 * - **The copy will not.** The approved BTCMap wording (BIT-56) deliberately names
 *   no provider, so it reads identically whoever serves the tiles. A host swap is
 *   not a copy change and will not come back through a copy review.
 * - **The app will not.** A vendor style URL renders *better* than a half-built
 *   pipeline — faster, complete, free at low volume. It looks like the change
 *   working, not like a regression.
 * - **A source review might not.** The single most likely way a vendor host lands
 *   here is not a decision at all: every MapLibre quickstart on the internet starts
 *   from `https://demotiles.maplibre.org/style.json`, and it is on [BANNED_HOSTS]
 *   for exactly that reason. It is the shape of the precise-location problem
 *   `map-sdk-decision.md` describes — the risk arrives by copy-paste, not by choice.
 *   (That permission is deliberately not spelled out here: `LocationPrecisionGuardTest`
 *   scans Kotlin sources for its name, comments included, and a guard's prose should
 *   not cost another guard its precision.)
 *
 * ### What these scan today
 *
 * The map screen *has* landed: `feature/map` renders through `BasemapController`,
 * and `MapBasemap.STYLE_URI` is the one configuration point the decision promised
 * to keep. It is currently `null`, so the renderer paints a background-only style
 * and **no tile request leaves the device at all**.
 *
 * That makes [the basemap style URI is null or a bittr host] the check with real
 * teeth, and it is deliberately separate from the other two. A style URL is not
 * required to look like a tile URL: `https://tiles.example.net/basemap` contains no
 * `{z}`, no `style.json` and no archive extension, and its host is not a vendor
 * anyone thought to ban — so it escapes both scans below while being exactly the
 * change BIT-73 exists to prevent. Reading the literal out of the file that holds
 * it is the only check that cannot be evaded by choosing an unfamiliar hostname.
 */
class TileHostGuardTest {

    private companion object {

        /**
         * Tile and style hosts that must not appear anywhere the app can read one.
         *
         * Three kinds of entry, all excluded for different reasons:
         *
         * - **Commercial tile vendors** (`maptiler`, `mapbox`, `stadiamaps`,
         *   `thunderforest`, `cartocdn`, `protomaps.com`, `openfreemap`) — each one
         *   reinstates the third party the tile-hosting decision removed. Protomaps
         *   is on the list despite being the upstream this pipeline builds *from*:
         *   mirroring their archive is fine, pointing the app at their API is not,
         *   and the difference is invisible in a diff unless something asserts it.
         * - **The OSM Foundation's own tile servers** (`tile.openstreetmap.org`,
         *   `tile.osm.org`) — excluded on grounds that are not privacy at all. Their
         *   tile usage policy is not something a consumer app is entitled to lean
         *   on, which `map-sdk-decision.md` already gives as a reason osmdroid was
         *   dropped.
         * - **MapLibre's demo tiles** (`demotiles.maplibre.org`) — not a product, a
         *   quickstart fixture, and the likeliest accident here.
         */
        val BANNED_HOSTS = listOf(
            "maptiler.com",
            "mapbox.com",
            "tile.openstreetmap.org",
            "tile.osm.org",
            "stadiamaps.com",
            "thunderforest.com",
            "cartocdn.com",
            "protomaps.com",
            "openfreemap.org",
            "demotiles.maplibre.org",
            "googleapis.com/maps",
        )

        /**
         * Hosts the map is allowed to fetch a basemap from.
         *
         * Both apex domains, matched with their subdomains, because the serving
         * hostname `tile-pipeline.md` settles on (`tiles.getbittr.com`) does not
         * exist yet. A CDN in front of it is only acceptable *under one of these
         * names* — see that document on why a vendor hostname in the request path
         * would fail the BIT-52 proxy capture even when bittr owns the bucket.
         */
        val BITTR_HOSTS = listOf("getbittr.com", "bittr.ch")

        /**
         * What makes a URL a basemap URL rather than any other URL in the repo.
         *
         * Matching on "is it a URL" would drag in the BTCMap API, the bittr backend
         * and every documentation link. These markers are what a tile source looks
         * like and nothing else does: an XYZ template, a style descriptor, or one of
         * the two archive formats MapLibre can read directly.
         */
        val TILE_URL_MARKERS = listOf("{z}", "{x}", "{y}", "style.json", ".pmtiles", ".mbtiles")

        /** `https://host/...` — group 1 is the host. */
        val URL: Pattern = Pattern.compile("""https?://([A-Za-z0-9._-]+)(/[^\s"'<>)]*)?""")

        /**
         * The file holding the one tile-host configuration point, and the literal in
         * it. Named rather than discovered: if it is renamed, this guard should fail
         * loudly rather than find nothing and pass.
         */
        const val BASEMAP_FILE = "MapBasemap.kt"

        val STYLE_URI: Pattern =
            Pattern.compile("""STYLE_URI\s*:\s*String\?\s*=\s*(null|"([^"]*)")""")

        /** Files that state these rules rather than break them. */
        val ALLOWED_FILES = arrayOf("TileHostGuardTest.kt")

        /**
         * The detectors, as pure functions so they can be run against known
         * offenders in [the detectors fire on known violations] as well as against
         * the tree.
         */
        fun bannedHostHit(text: String): String? = BANNED_HOSTS.firstOrNull { it in text }

        fun foreignBasemapUrls(text: String): List<String> {
            val matcher = URL.matcher(text)
            val offenders = mutableListOf<String>()
            while (matcher.find()) {
                val url = matcher.group(0) ?: continue
                val host = matcher.group(1) ?: continue
                if (TILE_URL_MARKERS.none { it in url }) continue
                if (isBittrHost(host)) continue
                offenders += url
            }
            return offenders
        }

        fun isBittrHost(host: String): Boolean =
            BITTR_HOSTS.any { host == it || host.endsWith(".$it") }

        /**
         * The `STYLE_URI` literal, or null when the declaration is not found —
         * which the caller treats as a failure, not as a pass.
         */
        fun styleUriLiteral(text: String): Result? {
            val matcher = STYLE_URI.matcher(text)
            if (!matcher.find()) return null
            val url = matcher.group(2)
            return if (url == null) Result.Null else Result.Url(url)
        }

        /** Whichever way [styleUriLiteral] read the declaration. */
        sealed interface Result {
            object Null : Result

            data class Url(val value: String) : Result
        }

        /**
         * Kotlin is read with comments stripped and string literals kept, which is
         * what `SourceTree.code` is for: the question here is what value the code
         * *holds*, and a KDoc naming a rejected vendor is documentation, not a
         * request path. Everything else is read raw — a resource or a manifest
         * placeholder has no comment convention worth modelling.
         */
        fun readableText(file: java.io.File): String =
            if (file.extension == "kt") file.code() else file.readText()
    }

    @Test
    fun `no tile vendor host is reachable from the app`() {
        val offenders = SourceTree.runtimeConfigSources(*ALLOWED_FILES)
            .mapNotNull { file ->
                val hit = bannedHostHit(readableText(file)) ?: return@mapNotNull null
                "${file.repoPath()} (references $hit)"
            }

        assertTrue(
            "A tile or style host bittr ruled out is reachable from the app.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "Every renderer that fetches tiles sends the viewport and the client IP to " +
                "whoever serves them, on every pan and every zoom — and on first open that " +
                "viewport is approximately where the user is. Ruben's call on BIT-53 was that " +
                "the party who learns that is bittr and nobody else; this line puts a vendor " +
                "back in that path.\n" +
                "Nothing else will flag it. The approved BTCMap copy names no provider, so it " +
                "reads the same either way, and a vendor's tiles render better than a " +
                "half-built pipeline rather than worse. Read android/docs/tile-pipeline.md, " +
                "and raise it on BIT-73 before editing this test.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `every basemap URL in the app points at a bittr host`() {
        val offenders = SourceTree.runtimeConfigSources(*ALLOWED_FILES)
            .flatMap { file ->
                foreignBasemapUrls(readableText(file)).map { "${file.repoPath()} ($it)" }
            }

        assertTrue(
            "A basemap URL in this repo points somewhere that is not bittr.\n" +
                "Offending URLs:\n  " + offenders.joinToString("\n  ") + "\n" +
                "This is the broader half of the pair: the banned-host list above catches the " +
                "vendors that were considered and rejected, and this catches the one nobody " +
                "thought to list. Any host serving the basemap receives the viewport plus the " +
                "client IP on every pan, whoever it is and whether or not bittr has heard of " +
                "them.\n" +
                "If bittr is serving tiles from a hostname that is not in $BITTR_HOSTS, that is " +
                "a real change and belongs in android/docs/tile-pipeline.md — add it there and " +
                "here in the same commit, so the list stays the answer to \"who does the map " +
                "talk to\".",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the basemap style URI is null or a bittr host`() {
        val file = SourceTree.runtimeConfigSources()
            .singleOrNull { it.name == BASEMAP_FILE }

        assertTrue(
            "Expected exactly one $BASEMAP_FILE under the android tree, holding the single " +
                "tile-host configuration point the BIT-53 decision promised to keep. Found " +
                "${if (file == null) "none or several" else "one"}. If the basemap source " +
                "moved, point this guard at its new home in the same commit — otherwise the " +
                "check below silently stops covering anything.",
            file != null,
        )
        requireNotNull(file)

        val literal = styleUriLiteral(file.code())
        assertTrue(
            "Could not find the STYLE_URI declaration in ${file.repoPath()}. This guard reads " +
                "the literal directly because that is the only check a hostname nobody thought " +
                "to ban cannot slip past. If the declaration was reshaped, reshape the pattern " +
                "with it.",
            literal != null,
        )

        if (literal is Result.Url) {
            val matcher = URL.matcher(literal.value)
            val host = if (matcher.find()) matcher.group(1) else literal.value
            assertTrue(
                "MapBasemap.STYLE_URI points at '$host', which is not a bittr host.\n" +
                    "This is the one line that decides who receives the viewport and the " +
                    "client IP on every pan. BIT-53 settled that it is bittr; BIT-73 is the " +
                    "pipeline that makes that possible. Setting this to anything else — " +
                    "including 'just for development', which is the case the decision calls " +
                    "out by name — reinstates the third party the copy was written to avoid " +
                    "conceding, and would fail the BIT-52 proxy capture.\n" +
                    "Allowed: null (background-only style, no tile request at all) or a host " +
                    "under $BITTR_HOSTS.",
                isBittrHost(host),
            )
        }
    }

    @Test
    fun `the detectors fire on known violations`() {
        assertEquals(
            "The banned-host detector no longer flags a vendor style URL. Until that is " +
                "fixed the tree scan proves nothing — it would report green against a build " +
                "pointed at MapTiler.",
            "maptiler.com",
            bannedHostHit("""val style = "https://api.maptiler.com/maps/streets/style.json"""),
        )

        assertEquals(
            "The banned-host detector flags a file with no vendor host in it. It will be " +
                "treated as a false positive and worked around, which disarms it.",
            null,
            bannedHostHit("""val places = "https://api.btcmap.org/v4/places""""),
        )

        assertEquals(
            "The foreign-basemap detector no longer flags a tile URL on an unfamiliar host — " +
                "the case the banned list cannot cover.",
            listOf("https://tiles.example.net/basemap/{z}/{x}/{y}.pbf"),
            foreignBasemapUrls("""val t = "https://tiles.example.net/basemap/{z}/{x}/{y}.pbf""""),
        )

        assertEquals(
            "The foreign-basemap detector flags a bittr-hosted basemap. The pipeline BIT-73 " +
                "builds would fail its own guard.",
            emptyList<String>(),
            foreignBasemapUrls("""val t = "https://tiles.getbittr.com/ch/style.json""""),
        )

        assertEquals(
            "The foreign-basemap detector flags a non-basemap URL, so every API and " +
                "documentation link in the tree becomes an offender.",
            emptyList<String>(),
            foreignBasemapUrls("""val api = "https://api.btcmap.org/v4/places""""),
        )

        assertEquals(
            "The STYLE_URI reader no longer recognises the null declaration it has to read " +
                "today, so the check that has real teeth would skip itself.",
            Result.Null,
            styleUriLiteral("""    val STYLE_URI: String? = null"""),
        )

        assertEquals(
            "The STYLE_URI reader no longer recognises a set declaration, which is the only " +
                "state worth checking.",
            Result.Url("https://tiles.example.net/basemap"),
            styleUriLiteral("""val STYLE_URI: String? = "https://tiles.example.net/basemap""""),
        )
    }
}
