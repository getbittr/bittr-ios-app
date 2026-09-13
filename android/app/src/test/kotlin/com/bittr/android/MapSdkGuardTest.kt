package com.bittr.android

import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Holds the map stack to the shape the shipped location claim depends on (BIT-53).
 *
 * The full reasoning, including what each candidate SDK transmits and to whom, is
 * in `android/docs/map-sdk-decision.md`. This file enforces the three properties of
 * that decision that a later change could quietly undo, because each of them breaks
 * a sentence bittr has shipped rather than breaking the app:
 *
 * 1. **MapLibre Native, not Google Maps and not Mapbox.** Every renderer that
 *    fetches tiles sends the viewport and the client IP to whoever serves them —
 *    unavoidable, and the approved copy now says so. What separates the candidates
 *    is the *second* channel: Google's Maps SDK additionally transmits, by its own
 *    published Play data disclosure, device metadata, IP, a pseudonymous Maps-SDK
 *    identifier used to count daily active users, and "interaction data, such as
 *    panning and zooming the map". An identifier plus pan/zoom plus IP, at one
 *    vendor, composes into a location trail keyed to a persistent ID. Mapbox ships
 *    vendor telemetry in the SDK — the specific thing MapLibre forked to remove.
 * 2. **The places sync downloads the whole dataset and filters on-device.** This is
 *    the reason bittr can say a user's location never leaves their device at all.
 *    A bounding-box query is cheaper and would silently end that. Latent until the
 *    map screen lands — see the test's own note; it has nothing to scan yet.
 * 3. **Coarse location only.** Asserted from the merged manifest here and from four
 *    angles in [LocationPrecisionGuardTest].
 *
 * ### Why these are tests and not a review comment
 *
 * Swapping the renderer is one line in `libs.versions.toml`, and switching the sync
 * to a bbox query is a faster app that passes every flow. Neither shows up as a bug
 * report. The only thing that changes is which third party learns where a user is.
 *
 * The approved copy will not catch either one. The BIT-56 wording deliberately names
 * no provider (`shared/strings/en.json`, `mapvcpoweredbyalert`, mirrored in
 * `ios/bittr/Language.swift:595`) so that one shared string survives the tile host
 * differing per platform. That is the right call for the copy, and it removes the
 * second place a renderer swap could have been noticed: the paragraph reads the same
 * whoever serves the tiles, including when the vendor behind them has started sending
 * pan/zoom and a persistent identifier home. So the build is the only tripwire left,
 * which is why these are tests.
 *
 * Do not quote that string here. It has been redrafted twice while this file existed;
 * what these tests depend on is the property that it names no provider, not its
 * wording.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class MapSdkGuardTest {

    private companion object {

        /**
         * Map and location artefacts that are not available to this app, by Gradle
         * coordinate fragment.
         *
         * `play-services-location` is on the list for the same reason as the map
         * SDKs even though it draws nothing: it is the fused location provider
         * Google's own map documentation steers integrators towards, it routes the
         * position fix through Play services, and its whole reason for existing is
         * accuracy the approved copy says bittr does not want. MapLibre's default
         * engine is `MapLibreFusedLocationEngineImpl`, built on the platform
         * `LocationManager`, and Play services is opt-in rather than the default —
         * so nothing needs this to work.
         */
        val BANNED_ARTEFACTS = listOf(
            "play-services-maps",
            "play-services-location",
            "com.mapbox",
            "mapbox-android",
            "osmdroid",
        )

        /** The chosen renderer, by Gradle coordinate. */
        const val CHOSEN_SDK = "org.maplibre.gl"

        /**
         * How a Kotlin file is recognised as the places sync.
         *
         * The viewport scan is gated on one of these so that `bbox` in an unrelated
         * file — a tile URL template, a test fixture — is not a failure. `btcmap`
         * alone would have missed a repository class named after the model rather
         * than the host, so the iOS type name is here too
         * (`BitcoinPlace.swift`).
         */
        val PLACES_SOURCE_MARKERS = listOf("btcmap", "bitcoinplace", "bitcoin_place")

        /**
         * Query keys that turn the places sync into a request that describes where
         * the user is looking.
         *
         * iOS sends `fields`, `include_deleted` and `updated_since` and nothing else
         * (`BitcoinPlace.swift:37-55`), then filters `allCachedPlaces` in-process
         * (`MapVCLocations.swift:91-110`). Anything here in the same file as a
         * BTCMap URL means that property is gone.
         */
        val VIEWPORT_QUERY_KEYS = listOf(
            "bbox",
            "boundingBox",
            "bounding_box",
            "min_lat",
            "max_lat",
            "min_lon",
            "max_lon",
            "sw_lat",
            "ne_lat",
            "viewport",
            "&lat=",
            "&lon=",
        )

        /**
         * Files that state these rules rather than break them.
         *
         * Only the Kotlin scan needs this — the artefact scan reads build files,
         * and this one is not a build file.
         *
         * [LocationEgressGuardTest] is here because it guards the same property from
         * the other side: it bans `boundingBox` as a coordinate symbol and names
         * BTCMap while doing so, which is both of this scan's triggers. It was
         * written on BIT-100 while this file was written on BIT-53, so neither
         * allow-list knew about the other until both landed on `android-parity`.
         * Excluding it keeps the scan pointed at code that builds requests. If a
         * third guard ever states these rules, add it here rather than widening
         * [PLACES_SOURCE_MARKERS] or [VIEWPORT_QUERY_KEYS] — narrowing either one
         * is how the check stops catching the thing it exists for.
         */
        val ALLOWED_FILES = setOf("MapSdkGuardTest.kt", "LocationEgressGuardTest.kt")

        const val COARSE = "android.permission.ACCESS_COARSE_LOCATION"
    }

    @Test
    fun `no banned map or location artefact is on the dependency graph`() {
        val offenders = SourceTree.buildFiles()
            .mapNotNull { file ->
                val text = file.readText()
                val hit = BANNED_ARTEFACTS.firstOrNull { it in text } ?: return@mapNotNull null
                "${file.repoPath()} (declares $hit)"
            }

        assertTrue(
            "A map or location artefact bittr ruled out is on the dependency graph. The " +
                "choice of renderer is a privacy constraint here, not a preference: Google's " +
                "Maps SDK transmits pan/zoom interaction data, the client IP and a " +
                "pseudonymous per-install identifier to one vendor, which composes into a " +
                "location trail keyed to a persistent ID, and Mapbox ships vendor telemetry " +
                "in the SDK. Both also have to be declared in the Play data-safety form " +
                "(BIT-15), where the responsibility is bittr's and not the SDK's.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "Read android/docs/map-sdk-decision.md before changing this, and raise it on " +
                "BIT-53. Do not expect the copy to stop you: it names no provider, so it reads " +
                "the same with either of these in the build.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the chosen renderer is still the one on the dependency graph`() {
        val declared = SourceTree.buildFiles().any { CHOSEN_SDK in it.readText() }

        assertTrue(
            "No build file declares $CHOSEN_SDK. This test exists so that removing MapLibre " +
                "is a deliberate act rather than a side effect. Nothing else will flag it: the " +
                "approved map copy names no provider, so a renderer swap is not automatically " +
                "a copy change and will not come back through a copy review — which is exactly " +
                "why the check has to live here. MapLibre was chosen " +
                "because it sends nothing to its own vendor; a replacement that does is a " +
                "privacy regression the wording would not reveal. If the map is being rebuilt " +
                "on something else, update android/docs/map-sdk-decision.md and raise it on " +
                "BIT-53 before this test is edited.",
            declared,
        )
    }

    /**
     * **This one passes vacuously today, and that is not a bug — but do not read a
     * green run as "the sync property is enforced".** No Kotlin file in the repo
     * matches [PLACES_SOURCE_MARKERS] yet, because the Android map screen has not
     * landed, so there is nothing for it to scan. It is here now so that it is
     * already in place on the commit that writes the first BTCMap request, rather
     * than being remembered afterwards. The property it defends is real from the
     * moment that request exists; until then, only the other three guards in this
     * class are actually holding anything.
     */
    @Test
    fun `the places sync does not ask for a viewport`() {
        val offenders = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .filter { file ->
                val text = file.readText().lowercase()
                PLACES_SOURCE_MARKERS.any { it in text }
            }
            .mapNotNull { file ->
                val text = file.readText()
                val hit = VIEWPORT_QUERY_KEYS.firstOrNull { it in text } ?: return@mapNotNull null
                "${file.repoPath()} (builds a request with $hit)"
            }

        assertTrue(
            "A BTCMap request in this repo carries the map's viewport. That request is the " +
                "one place bittr's strongest location claim lives: iOS downloads the whole " +
                "dataset — fields, include_deleted, updated_since, nothing else — and filters " +
                "it on the device, which is why bittr can say a user's location never leaves " +
                "their phone. A bounding-box query is cheaper, renders identically, and ends " +
                "that property silently: the first request after the map centres on the user " +
                "*is* their approximate position, timestamped and attached to an IP.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "Port the iOS design (BitcoinPlace.swift:37-55, MapVCLocations.swift:91-110). " +
                "If the dataset has grown too large to download, that is a BIT-53 " +
                "conversation, not a local optimisation.",
            offenders.isEmpty(),
        )
    }

    /**
     * The positive half of the permission claim, and the reason this test survives
     * the map screen landing: the app must ask for coarse location and get it.
     *
     * [LocationPrecisionGuardTest] proves precise location is absent, which an app
     * that requests no location at all would also pass. This proves the merged
     * manifest still contains the permission the approved copy describes, so
     * "centre the map on where you are" keeps working for a reason the build can
     * check.
     */
    @Test
    fun `the merged manifest requests approximate location`() {
        val context = RuntimeEnvironment.getApplication()
        val requested = context.packageManager
            .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            ?.toList()
            .orEmpty()

        assertTrue(
            "The merged manifest does not request $COARSE. The approved map copy (DEV-54) " +
                "says bittr needs your approximate location to centre the map — with no " +
                "location permission at all, the my-location button cannot work and the " +
                "sentence describes something the app does not do. Declare it in " +
                "app/src/main/AndroidManifest.xml; request it as BittrPermissions.LOCATION.\n" +
                "Merged permission set: $requested",
            COARSE in requested,
        )
    }
}
