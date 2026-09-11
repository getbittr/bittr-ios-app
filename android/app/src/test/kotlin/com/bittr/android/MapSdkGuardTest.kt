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
 *    A bounding-box query is cheaper and would silently end that.
 * 3. **Coarse location only.** Asserted from the merged manifest here and from four
 *    angles in [LocationPrecisionGuardTest].
 *
 * ### Why these are tests and not a review comment
 *
 * Swapping the renderer is one line in `libs.versions.toml`, and switching the sync
 * to a bbox query is a faster app that passes every flow. Neither shows up as a bug
 * report. The only thing that changes is which third party learns where a user is,
 * and whether `Language.swift`'s map paragraph is still true.
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
         */
        val ALLOWED_FILES = setOf("MapSdkGuardTest.kt")

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
                "BIT-53 — the user-facing copy names the provider, so a swap is a copy change.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the chosen renderer is still the one on the dependency graph`() {
        val declared = SourceTree.buildFiles().any { CHOSEN_SDK in it.readText() }

        assertTrue(
            "No build file declares $CHOSEN_SDK. This test exists so that removing MapLibre " +
                "is a deliberate act rather than a side effect: the approved map copy names " +
                "the provider that serves bittr's tiles, so the renderer and the copy have to " +
                "move together. If the map is being rebuilt on something else, update " +
                "android/docs/map-sdk-decision.md and tell the Growth & Content Lead before " +
                "this test is edited.",
            declared,
        )
    }

    @Test
    fun `the places sync does not ask for a viewport`() {
        val offenders = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .filter { "btcmap" in it.readText().lowercase() }
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
