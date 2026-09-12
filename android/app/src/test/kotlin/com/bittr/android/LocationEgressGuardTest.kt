package com.bittr.android

import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Keeps the map's approved reassurance true: the user's location **isn't sent to
 * bittr**.
 *
 * Ruben approved this sentence on 2026-09-11 (`approve_with_sentence`, BIT-15). It
 * is part of the specified copy for both location states (DEV-54, BIT-15 →
 * `decision-brief` §D3), not an optional extra:
 *
 * > Your location is used on your device to position the map. It isn't sent to bittr.
 *
 * Like "approximate" and "nothing is recorded", approving it is what makes it
 * binding: it is a factual claim about where a value goes, and the build is the
 * only thing that can keep it true. It verifies on iOS today — the BTCMap request
 * carries `fields`, `include_deleted` and `updated_since` and no coordinates and no
 * bounding box (`Map/BitcoinPlace.swift:37-55`), and proximity filtering happens
 * on-device (`Map/MapVCLocations.swift:91-110`).
 *
 * ### Read the boundary before you extend this test
 *
 * The sentence says *isn't sent to bittr* and **stops there, on purpose**. It is
 * deliberately **not** a claim that the location never leaves the device. Centring
 * the map makes the renderer fetch tiles for the area around the user, and the
 * Android renderer has not been chosen yet (BIT-52, BIT-53). So:
 *
 * - Tile requests for the region around the user are **allowed**. They are what
 *   centring the map *is*. This test must never be "fixed" by banning them.
 * - Coordinates in a request body or an analytics event are **not**, because those
 *   are the two ways the value reaches bittr.
 *
 * Do not let the implementation drift toward *"stays on your device"* or *"never
 * shared with third parties"*. Those are overclaims here. bittr already ships a
 * broader version of exactly that claim on iOS (`mapvcpoweredbyalert`,
 * `Language.swift:595`) and it is under separate review as BIT-45 / BIT-56 — this
 * test is not the place to settle it.
 *
 * ### Why this is written against a vocabulary rather than a type
 *
 * There is no networking layer and no map in this tree yet, so there is no type to
 * hang the rule on, and inventing one would not help: whoever builds the map will
 * reach for whatever coordinate type their SDK hands them. The rule is therefore
 * written against the words a coordinate travels under. That catches the SDK's own
 * `LatLng` as readily as one of ours.
 *
 * Because the tree contains nothing to catch today, every scan here would pass
 * while detecting nothing — the exact failure mode [SourceTree] exists to prevent.
 * [the detector fires on a known violation] closes that hole by running the
 * detector against a synthetic offender, so a regression in the *detector* fails
 * the build rather than quietly disarming the guard.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class LocationEgressGuardTest {

    private companion object {

        /**
         * The words a user coordinate travels under.
         *
         * Deliberately not the bare word `Location`: it is half the Android
         * location API's surface (`LocationManager`, `FusedLocationProviderClient`)
         * and using it would flag every legitimate call site. What is being looked
         * for is a *coordinate*, which is the thing that would be transmitted.
         */
        val COORDINATE_SYMBOLS = listOf(
            "latitude",
            "longitude",
            "LatLng",
            "LatLon",
            "GeoPoint",
            "boundingBox",
            "BoundingBox",
        )

        /**
         * Markers that a file turns values into something that leaves the process.
         *
         * Serialization annotations cover the DTO route — a coordinate added as a
         * field to a request model, which is the likeliest way this breaks and the
         * hardest to see in a diff. The Retrofit parameter annotations and the
         * hand-rolled JSON builders cover the call-site route.
         */
        val EGRESS_MARKERS = listOf(
            "@Serializable",
            "@SerialName",
            "@SerializedName",
            "@JsonClass",
            "@Json(",
            "@Body",
            "@Query",
            "@Field",
            "@FormUrlEncoded",
            "RequestBody",
            "buildJsonObject",
            "JSONObject(",
        )

        /**
         * Gradle coordinates for analytics, telemetry and crash SDKs.
         *
         * Empty allowlist, and that is the point: there is no analytics in this app
         * today, so the cheapest way to keep a coordinate out of an analytics event
         * is that there is no event to put it in. This is a **tripwire, not a ban**.
         * Adding one of these is a legitimate thing to want; it just has to arrive
         * with an answer to "what keeps the user's coordinate out of it", which is
         * a conversation on BIT-57 and not a line appended to this list.
         */
        val ANALYTICS_ARTEFACTS = listOf(
            "firebase-analytics",
            "firebase-crashlytics",
            "play-services-measurement",
            "com.amplitude",
            "com.mixpanel",
            "io.sentry",
            "com.segment",
            "com.appsflyer",
            "com.posthog",
        )

        /**
         * Continuous-fix APIs.
         *
         * iOS takes a **single** fix — `requestLocation()` at
         * `MapVCLocations.swift:38, 47, 190` — and centres once. There is no
         * `startUpdatingLocation` and no user-tracking mode anywhere in the app,
         * and that fact is load-bearing: it is why compliance corrected the
         * approved rationale from "it just won't *follow* you" to "it just won't
         * *centre* on you" (§D3). A subscription does not falsify a single word the
         * way a capture use case or a precise-location request would — it re-opens
         * the correction that produced the approved wording, and turns "used to
         * position the map" into a standing stream. Either way the answer is the
         * same: raise it before it ships.
         *
         * `getCurrentLocation` is the single-fix equivalent and is deliberately
         * absent.
         */
        val CONTINUOUS_FIX_SYMBOLS = listOf(
            "requestLocationUpdates",
            "startUpdatingLocation",
            "LocationListener",
            "locationFlow",
            "isMyLocationEnabled",
        )

        /** Files that state these rules rather than break them. */
        val ALLOWED_FILES = setOf("LocationEgressGuardTest.kt")

        const val BACKGROUND = "android.permission.ACCESS_BACKGROUND_LOCATION"

        /**
         * The detector, as a pure function so it can be run against a known
         * offender in [the detector fires on a known violation] as well as against
         * the tree.
         *
         * Whole-file co-occurrence rather than same-line: a `@Serializable` sits on
         * the class, and the coordinate it exposes is a property several lines
         * below it. Checking the line would miss precisely the shape being looked
         * for. The cost is that a file both serializing something unrelated *and*
         * mentioning a coordinate in a comment is flagged — rare, obvious from the
         * message, and [ALLOWED_FILES] is the escape.
         */
        fun egressHit(text: String): String? {
            val coordinate = COORDINATE_SYMBOLS.firstOrNull { it in text } ?: return null
            val marker = EGRESS_MARKERS.firstOrNull { it in text } ?: return null
            return "$coordinate alongside $marker"
        }
    }

    @Test
    fun `no coordinate is reachable from a serialized payload`() {
        val offenders = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .mapNotNull { file -> egressHit(file.readText())?.let { "${file.repoPath()} ($it)" } }

        assertTrue(
            "The map's approved copy says your location \"isn't sent to bittr\" (DEV-54, " +
                "approved 2026-09-11). A coordinate has appeared in a file that serializes " +
                "values, which is how that sentence stops being true: a field added to a " +
                "request model reads like any other field in review, and nothing else in the " +
                "build can tell you a shipped promise just broke.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "Note the boundary before assuming this is a false positive: fetching map " +
                "tiles for the area around the user is allowed and is not what this catches. " +
                "Putting the coordinate in a body, a query parameter or an event is. If bittr " +
                "genuinely needs the coordinate server-side, raise it on BIT-57 before it " +
                "ships — the copy changes first, and changed copy goes back through compliance.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `no analytics SDK is on the dependency graph`() {
        val offenders = SourceTree.buildFiles()
            .mapNotNull { file ->
                val text = file.readText()
                val hit = ANALYTICS_ARTEFACTS.firstOrNull { it in text } ?: return@mapNotNull null
                "${file.repoPath()} (declares $hit)"
            }

        assertTrue(
            "An analytics or telemetry SDK has been added. This test is a tripwire, not a " +
                "veto — but the approved map copy says the user's location \"isn't sent to " +
                "bittr\", and an analytics SDK is the second of the two ways it gets there. " +
                "Automatic screen and event collection is the part to check: it does not need " +
                "anyone to pass a coordinate deliberately.\n" +
                "Declared in:\n  " + offenders.joinToString("\n  ") + "\n" +
                "Bring it to BIT-57 with an answer for what keeps the coordinate out, rather " +
                "than adding the artefact to ANALYTICS_ARTEFACTS' allowlist here.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the map takes a single fix rather than subscribing`() {
        val offenders = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .mapNotNull { file ->
                val text = file.readText()
                val hit = CONTINUOUS_FIX_SYMBOLS.firstOrNull { it in text } ?: return@mapNotNull null
                "${file.repoPath()} (references $hit)"
            }

        assertTrue(
            "The approved location rationale says the map won't \"centre on you\" without " +
                "permission — compliance corrected that line from \"follow you\" precisely " +
                "because iOS takes a single fix (requestLocation() at MapVCLocations.swift:38, " +
                "47, 190) and centres once, with no startUpdatingLocation anywhere in the app " +
                "(BIT-15 → decision-brief §D3). A subscription makes the app do the following " +
                "the approved copy was corrected to stop describing.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "Use getCurrentLocation — one fix, centre, done. If the map genuinely needs to " +
                "track, that is a copy change and it goes back through compliance first.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the merged manifest requests no background location`() {
        val context = RuntimeEnvironment.getApplication()
        val requested = context.packageManager
            .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            ?.toList()
            .orEmpty()

        assertTrue(
            "The merged manifest requests $BACKGROUND. The approved copy says the location is " +
                "\"used on your device to position the map\" — collecting it while the map is " +
                "not on screen is not that, and it is the one location permission Play reviews " +
                "by hand (BIT-51). As with precise location, the realistic way it arrives is a " +
                "dependency declaring it in its own manifest rather than anyone typing it.\n" +
                "Merged permission set: $requested",
            BACKGROUND !in requested,
        )
    }

    /**
     * Proves the detector detects.
     *
     * Everything above scans a tree that currently contains no map, no networking
     * and no analytics, so all of it passes without examining a single real
     * offender. That is worth very little on its own, and it is worth *less* than
     * nothing if the detector silently stops working — the guard would go on
     * reporting green while enforcing nothing, which is the failure mode these
     * tests exist to make impossible.
     *
     * So run it against a request model of the shape this rule is about: the
     * smallest change that would break the shipped sentence.
     */
    @Test
    fun `the detector fires on a known violation`() {
        val offender =
            """
            @Serializable
            data class PlacesNearbyRequest(
                @SerialName("lat") val latitude: Double,
                @SerialName("lon") val longitude: Double,
            )
            """.trimIndent()

        assertEquals(
            "The coordinate-egress detector no longer flags a request model carrying the " +
                "user's coordinate. Until that is fixed the other scans in this class prove " +
                "nothing — they would report green against a tree that had this in it.",
            "latitude alongside @Serializable",
            egressHit(offender),
        )

        assertEquals(
            "The detector flags a file that serializes values but carries no coordinate. It " +
                "will be treated as a false positive and worked around, which disarms it.",
            null,
            egressHit("@Serializable\ndata class Quote(val amountSats: Long)"),
        )
    }
}
