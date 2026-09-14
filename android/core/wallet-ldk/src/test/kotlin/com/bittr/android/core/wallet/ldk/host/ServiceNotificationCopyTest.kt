package com.bittr.android.core.wallet.ldk.host

import android.app.Notification
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.bittr.android.core.wallet.ldk.R
import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Keeps the foreground-service notification identical to the canonical copy in
 * `shared/strings/en.json`.
 *
 * The three strings are permanently on screen while the wallet runs, which makes
 * them shipped copy: authored once in the shared tree, approved there, and
 * reaching both apps from there (`shared/strings/README.md`). The generator that
 * would make `strings.xml` a build artefact does not exist yet, so the README
 * says to keep the platform copies identical by hand — and a hand-kept copy with
 * nothing checking it is a copy that drifts. `:feature:map`'s `SharedStringsTest`
 * guards the other two keys the same way and for the same reason.
 *
 * What this pins is the *equality*, not a wording. An approved reword changes
 * `en.json` and `strings.xml` together and this stays green; a reword in one
 * file only — which is how an approval gets quietly bypassed — does not.
 *
 * The constraints the wording itself is under (no freshness claim, no amount,
 * nothing that reads as custody) are in `shared/strings/README.md`. They are not
 * assertable here: no string comparison can tell "Keeping your node connected"
 * from "Instant payments need the app running" on the axis that matters.
 *
 * Pinned at 34 rather than the module's 26/34/36 triple: a resource lookup does
 * not vary by API level, so the extra levels would buy nothing, and 34 is the
 * level the CI emulator boots.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ServiceNotificationCopyTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val canonical: JSONObject by lazy {
        // Gradle runs unit tests with the module directory as the working
        // directory: android/core/wallet-ldk -> three levels to the repo root.
        val file = File(File("../../..").canonicalFile, "shared/strings/en.json")
        assertTrue(
            "Expected the canonical strings at $file (working dir " +
                "${File(".").canonicalFile}). If the shared tree moved, point this test " +
                "at it — do not delete the test: the duplication it guards is what the " +
                "README asks for until the generator exists.",
            file.isFile,
        )
        JSONObject(file.readText())
    }

    @Test
    fun `the channel name matches the canonical copy`() {
        assertCanonical("wallet_node_service_channel", R.string.wallet_node_service_channel)
    }

    @Test
    fun `the notification title matches the canonical copy`() {
        assertCanonical("wallet_node_service_title", R.string.wallet_node_service_title)
    }

    @Test
    fun `the notification text matches the canonical copy`() {
        assertCanonical("wallet_node_service_text", R.string.wallet_node_service_text)
    }

    /**
     * The service shows what the resources say.
     *
     * Without this the three assertions above prove the two *files* agree while
     * the notification is built from something else entirely — a literal, or a
     * different resource — and the copy the user reads would be outside the
     * approval it is supposed to be inside.
     */
    @Test
    fun `the notification is built from the strings this test pins`() {
        val service = Robolectric.buildService(WalletForegroundService::class.java).create().get()
        service.onStartCommand(Intent(), 0, 1)

        val notification = shadowOf(service).lastForegroundNotification
        assertNotNull("the service never reached startForeground", notification)
        assertEquals(
            context.getString(R.string.wallet_node_service_title),
            notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
        )
        assertEquals(
            context.getString(R.string.wallet_node_service_text),
            notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
        )
    }

    private fun assertCanonical(key: String, resource: Int) {
        assertTrue(
            "$key is missing from shared/strings/en.json. The notification copy is " +
                "authored there and mirrored into this module's strings.xml; a resource " +
                "with no canonical entry is copy that was written in the app, which is " +
                "the thing BIT-127 removed.",
            canonical.has(key),
        )
        assertEquals(
            "$key has drifted from shared/strings/en.json. These three strings are " +
                "permanently on the user's screen while the wallet runs and are approved " +
                "in the shared tree under constraints recorded in " +
                "shared/strings/README.md — no freshness claim, no amount, nothing that " +
                "reads as custody. Change the canonical file and repeat the approval, or " +
                "restore this copy.",
            canonical.getString(key),
            context.getString(resource),
        )
    }
}
