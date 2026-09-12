package com.bittr.android

import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Keeps the map's approved copy true: bittr asks for your **approximate** location.
 *
 * The shipped map rationale (DEV-54, BIT-15 → `decision-brief` §D3) is:
 *
 * > To centre the map on where you are, bittr needs your approximate location.
 *
 * Compliance signed that off as binding on the build (BIT-36, BIT-57). On iOS it is
 * true because the map asks for `kCLLocationAccuracyHundredMeters`
 * (`Map/MapViewController.swift:80`). On Android the equivalent is
 * `ACCESS_COARSE_LOCATION` **and not `ACCESS_FINE_LOCATION`**.
 *
 * ### Why the permission is the claim, not the value the app reads
 *
 * It is tempting to think requesting FINE and then rounding the coordinate keeps
 * the sentence honest. It does not, for two reasons, and both are visible to the
 * user before any code runs:
 *
 * 1. **The system dialog changes.** Since Android 12, a FINE request renders the
 *    *Precise / Approximate* toggle with precise preselected. The user is being
 *    asked for their exact location, next to bittr's sentence saying it needs an
 *    approximate one. Coarse alone renders no toggle and can only grant
 *    approximate — so the sentence holds no matter what the user taps.
 * 2. **The store listing changes.** FINE surfaces as "precise location" in the
 *    Play listing's permission list (BIT-51), where the same contradiction is
 *    readable by someone who never installs the app.
 *
 * ### The two ways FINE arrives
 *
 * Someone types it — caught by [no location permission is named outside the
 * permissions module]. Or a **map SDK declares it in its own manifest** and the
 * merger unions it in, which no source scan can see; that is caught by the
 * `tools:node="remove"` directive in the app manifest and asserted here twice,
 * once against the source and once against the merged result. Worth knowing while
 * the map SDK is still being chosen — the choice also feeds BIT-45.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class LocationPrecisionGuardTest {

    private companion object {

        /**
         * Ways of asking for precise location.
         *
         * `ACCESS_COARSE_LOCATION` is absent on purpose — it is the approved path.
         * The last three are the non-permission routes to the same accuracy:
         * fused-location priority constants, the raw GPS provider, and the legacy
         * `Criteria` accuracy, none of which read as "fine location" at a glance.
         */
        val PRECISE_LOCATION_SYMBOLS = listOf(
            "ACCESS_FINE_LOCATION",
            "PRIORITY_HIGH_ACCURACY",
            "GPS_PROVIDER",
            "ACCURACY_FINE",
        )

        /**
         * Files allowed to name these, because they state the rule rather than use
         * it. Note that `BittrPermissions.kt` — the single approved place to name a
         * location permission — names only the coarse one, so it does not need to
         * be here.
         */
        val ALLOWED_FILES = setOf("LocationPrecisionGuardTest.kt")

        const val APP_MANIFEST = "app/src/main/AndroidManifest.xml"
        const val FINE = "android.permission.ACCESS_FINE_LOCATION"
    }

    @Test
    fun `no precise-location API is named in the app's Kotlin sources`() {
        val offenders = SourceTree.kotlinSources(*ALLOWED_FILES.toTypedArray())
            .mapNotNull { file ->
                val text = file.readText()
                val hit = PRECISE_LOCATION_SYMBOLS.firstOrNull { it in text }
                    ?: return@mapNotNull null
                "${file.repoPath()} (references $hit)"
            }

        assertTrue(
            "The map's approved copy says bittr needs your *approximate* location (DEV-54), " +
                "matching iOS's kCLLocationAccuracyHundredMeters. Request " +
                "BittrPermissions.LOCATION — ACCESS_COARSE_LOCATION — and nothing else. A " +
                "FINE request puts the Precise/Approximate toggle in front of the user, " +
                "preselected on precise, directly underneath the sentence saying bittr only " +
                "needs approximate; rounding the coordinate afterwards does not undo that.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  ") + "\n" +
                "If precise location is genuinely needed, raise it on BIT-57 before the map " +
                "ships: the copy changes first, and changed copy goes back through compliance.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `no manifest in the repo declares precise location`() {
        val offenders = SourceTree.manifests()
            .filter { file ->
                // Read <uses-permission> elements, not occurrences of the string:
                // the removal directive has to name FINE in order to delete it, and
                // so does the comment above it explaining why. Comments are stripped
                // first so prose about the rule can never look like a declaration.
                val xml = file.readText().replace(Regex("""<!--.*?-->""", RegexOption.DOT_MATCHES_ALL), "")
                Regex("""<uses-permission\b[^>]*>""", RegexOption.DOT_MATCHES_ALL)
                    .findAll(xml)
                    .map { it.value }
                    .filter { "ACCESS_FINE_LOCATION" in it }
                    .any { """tools:node\s*=\s*"remove"""".toRegex().containsMatchIn(it).not() }
            }
            .map { it.repoPath() }

        assertTrue(
            "A manifest in this repo declares ACCESS_FINE_LOCATION. Declaring it is what " +
                "makes the system dialog offer Precise, and what puts \"precise location\" " +
                "on the Play listing — both of which contradict the approved map copy.\n" +
                "Offending manifests:\n  " + offenders.joinToString("\n  "),
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the app manifest holds precise location out of the merge`() {
        val manifest = SourceTree.root.resolve(APP_MANIFEST)
        assertTrue("$APP_MANIFEST does not exist.", manifest.isFile)

        assertTrue(
            "$APP_MANIFEST no longer removes $FINE. That line is the only defence against " +
                "the way FINE actually arrives: a map or places SDK declaring it in its own " +
                "manifest, which the merger unions into the APK with no Kotlin change for " +
                "anyone to review. Restore:\n" +
                "  <uses-permission android:name=\"$FINE\" tools:node=\"remove\" />",
            Regex(
                """ACCESS_FINE_LOCATION"\s+tools:node="remove"""",
            ).containsMatchIn(manifest.readText()),
        )
    }

    /**
     * The claim that actually ships: the merged manifest, read back the way the
     * platform and the Play listing read it.
     *
     * The source tests above prove this repo neither declares FINE nor forgot the
     * removal directive. This one proves the result — a dependency using
     * `tools:replace`, or a merger precedence rule nobody expected, passes both of
     * those and fails this.
     */
    @Test
    fun `the merged manifest requests no precise location`() {
        val context = RuntimeEnvironment.getApplication()
        val requested = context.packageManager
            .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            ?.toList()
            .orEmpty()

        assertFalse(
            "The merged manifest requests $FINE, so the shipped APK asks for precise " +
                "location while the shipped copy says approximate. Find which dependency " +
                "declares it with `./gradlew :app:processDebugMainManifest` and read " +
                "app/build/outputs/logs/manifest-merger-debug-report.txt.\n" +
                "Merged permission set: $requested",
            FINE in requested,
        )
    }
}
