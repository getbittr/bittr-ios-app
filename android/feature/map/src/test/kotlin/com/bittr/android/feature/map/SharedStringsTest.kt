package com.bittr.android.feature.map

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Keeps the two BTCMap strings identical to the canonical ones in
 * `shared/strings/en.json`.
 *
 * They are the only strings in either app that already live there, because they
 * carry a privacy representation with a review trail: a compliance read (BIT-69) and
 * a factual check against the code (BIT-70), both against a specific wording. The
 * generator that would turn `shared/strings/` into `strings.xml` does not exist yet,
 * so `shared/strings/README.md` says to keep the platform copies identical by hand —
 * and a hand-kept copy with nothing checking it is a copy that drifts.
 *
 * Character for character on purpose. The reviewed artefact is the text, including
 * its em dash and its `<br><br>` paragraph breaks, and the length was measured
 * against a card that truncates the last paragraph first.
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class SharedStringsTest {

    private val canonical: JSONObject by lazy {
        // Gradle runs unit tests with the module directory as the working directory.
        val repoRoot = File("../../..").canonicalFile
        val file = File(repoRoot, "shared/strings/en.json")
        assertTrue(
            "Expected the canonical strings at $file (working dir ${File(".").canonicalFile}). " +
                "If the shared tree moved, point this test at it — do not delete the test: " +
                "the duplication it guards is what the README asks for until the generator " +
                "exists.",
            file.isFile,
        )
        JSONObject(file.readText())
    }

    @Test
    fun `the BTCMap credit matches the canonical copy`() {
        assertEquals(
            canonical.getString(MapCopy.Id.POWERED_BY),
            MapCopy.POWERED_BY,
        )
    }

    @Test
    fun `the BTCMap alert matches the canonical copy`() {
        assertEquals(
            "MapCopy.POWERED_BY_ALERT has drifted from shared/strings/en.json. This string " +
                "went through a compliance read and a factual check against a specific " +
                "wording (shared/strings/README.md), and it is the one paragraph of copy in " +
                "the app where a reword is a compliance problem rather than a typo. Change " +
                "the canonical file and repeat the reviews, or restore this copy.",
            canonical.getString(MapCopy.Id.POWERED_BY_ALERT),
            MapCopy.POWERED_BY_ALERT,
        )
    }

    /**
     * The claim the alert makes is about [bitcoinMapUrl]. Asserting the two together
     * is what keeps the review trail meaningful: the wording was cleared because the
     * request carries no position, so a test that checks only the wording checks half
     * of what was reviewed.
     */
    @Test
    fun `the request still supports what the alert claims`() {
        assertTrue(
            "The alert says the phone downloads the whole list and picks the nearby ones " +
                "out itself.",
            "whole list of places and picks out the nearby ones itself" in MapCopy.POWERED_BY_ALERT,
        )

        val url = bitcoinMapUrl(updatedSince = null, includeDeleted = false)
        val parameters = url.substringAfter("?").split("&").map { it.substringBefore("=") }
        assertEquals(
            "The sync asks for fields and tombstones and nothing about where the user is.",
            listOf("fields", "include_deleted"),
            parameters,
        )
    }
}
