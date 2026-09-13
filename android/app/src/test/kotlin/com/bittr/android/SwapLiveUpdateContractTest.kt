package com.bittr.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The platform half of `shared/docs/swap-live-activity-spec.md`, which is the porting spec for
 * iOS's swap Live Activity (`ios/BittrWidget/SwapLiveActivity.swift`).
 *
 * That document makes two claims the Android port is costed on, and both are platform facts
 * rather than facts about our code — so they are pinned here instead of only asserted in prose:
 *
 *  1. **§3.2 — `setRequestPromotedOngoing(true)` is not sufficient.** Requesting promotion does
 *     not grant it. `Notification.hasPromotableCharacteristics()` decides locally, and a
 *     notification that fails it is posted as an *ordinary* notification with no error and no
 *     log. For a `ProgressStyle` surface the non-obvious extra requirement is
 *     `setColorized(true)`. Getting this wrong is invisible in code review and on any device
 *     below API 36.
 *  2. **§3.3 — one builder covers `minSdk` 26 through 37.** The spec tells the implementer not
 *     to write a `Build.VERSION` branch for the pre-Live-Update range. That is only safe if the
 *     same builder degrades rather than throwing, which is asserted here at API 26.
 *
 * The Live Update itself does not exist yet — it is Phase 4 item 12 and depends on items 7 and 9
 * (see `ANDROID_PORT_PLAN.md`). When it lands, the phase table in the spec's §4 becomes
 * assertable the same way, and [notification] should be replaced by the real builder rather than
 * duplicated alongside it.
 *
 * Note on what this cannot prove: `FLAG_PROMOTED_ONGOING` is set by `NotificationManagerService`,
 * which Robolectric does not run, so the flag reads 0 here even for an eligible notification.
 * This test proves *eligibility*; that the system actually promotes it needs a device.
 */
@RunWith(AndroidJUnit4::class)
class SwapLiveUpdateContractTest {

    private companion object {
        const val CHANNEL = "swap-progress"
        const val ID = 7501

        /** Stands in for `waitingConfirmation` — the phase that shows a bar and a live timer. */
        const val TITLE = "Confirming your transfer"
        const val TEXT = "This usually takes 10-30 minutes"

        /** `Yellow` from the Android design tokens, not iOS's local `#FAC924`. See spec §4.2. */
        const val YELLOW = 0xFFFFC502.toInt()

        const val STARTED_AT_MILLIS = 1_000_000L
    }

    /**
     * The builder from the spec's §3.1, with the three properties under test parameterised so the
     * promotion guards can be probed from both sides.
     */
    private fun notification(
        context: Context,
        colorized: Boolean = true,
        ongoing: Boolean = true,
        style: NotificationCompat.Style = threeSegmentProgress(),
    ): Notification {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Swap progress", NotificationManager.IMPORTANCE_DEFAULT)
        )
        val built = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle(TITLE)
            .setContentText(TEXT)
            .setShortCriticalText("10m")
            .setStyle(style)
            .setOngoing(ongoing)
            .setColorized(colorized)
            .setRequestPromotedOngoing(true)
            .setWhen(STARTED_AT_MILLIS)
            .setUsesChronometer(true)
            .build()
        manager.notify(ID, built)
        // Read it back from the manager rather than trusting the builder: a style that the
        // platform rejects is dropped during the post, not during the build.
        return manager.activeNotifications.single { it.id == ID }.notification
    }

    /** Spec §4.3: preparing / waitingConfirmation / completing as 25-50-25. */
    private fun threeSegmentProgress() = NotificationCompat.ProgressStyle()
        .setProgressSegments(
            listOf(
                NotificationCompat.ProgressStyle.Segment(25).setColor(YELLOW),
                NotificationCompat.ProgressStyle.Segment(50).setColor(YELLOW),
                NotificationCompat.ProgressStyle.Segment(25).setColor(YELLOW),
            )
        )
        .setProgress(25)

    @Test
    @Config(sdk = [36])
    fun `progress style and chip survive the post on api 36`() {
        val posted = notification(ApplicationProvider.getApplicationContext())

        assertEquals(
            "ProgressStyle was dropped during the post — the Live Update would render as a plain notification",
            "android.app.Notification\$ProgressStyle",
            posted.extras.getString(Notification.EXTRA_TEMPLATE),
        )
        assertEquals("10m", posted.shortCriticalText)
        assertEquals(TITLE, posted.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertEquals(TEXT, posted.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals(25, posted.extras.getInt(Notification.EXTRA_PROGRESS))

        // setWhen + setUsesChronometer is the port of iOS's Text(startDate, style: .timer).
        // The timer origin must survive, or every update resets the elapsed count to zero.
        assertTrue(posted.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertEquals(STARTED_AT_MILLIS, posted.`when`)

        assertTrue("FLAG_ONGOING_EVENT lost", posted.flags and Notification.FLAG_ONGOING_EVENT != 0)
    }

    /**
     * Spec §3.2. `hasPromotableCharacteristics()` requires ongoing + a title + no group summary +
     * no custom views, and then either CallStyle or (colorized requested AND a promotable style:
     * null, BigTextStyle, CallStyle or ProgressStyle).
     */
    @Test
    @Config(sdk = [36])
    fun `promotion requires colorized ongoing and a promotable style`() {
        val context = ApplicationProvider.getApplicationContext<Context>()

        assertTrue(
            "colorized + ongoing + ProgressStyle should be promotion-eligible",
            notification(context).hasPromotableCharacteristics(),
        )
        assertFalse(
            "setColorized(true) is required for a non-CallStyle Live Update — this is the trap",
            notification(context, colorized = false).hasPromotableCharacteristics(),
        )
        assertFalse(
            "a notification that is not ongoing must not be promotion-eligible",
            notification(context, ongoing = false).hasPromotableCharacteristics(),
        )
        assertFalse(
            "InboxStyle is not a promotable style",
            notification(context, style = NotificationCompat.InboxStyle())
                .hasPromotableCharacteristics(),
        )
    }

    /**
     * Spec §3.3. API 26 is `minSdk`. The same builder must post without throwing and still render
     * the title, text and a determinate bar, so the implementation needs no version branch.
     */
    @Test
    @Config(sdk = [26])
    fun `the same builder degrades instead of throwing on min sdk`() {
        val posted = notification(ApplicationProvider.getApplicationContext())

        assertNull(
            "API 26 has no ProgressStyle template; expected the plain layout",
            posted.extras.getString(Notification.EXTRA_TEMPLATE),
        )
        assertEquals(TITLE, posted.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertEquals(25, posted.extras.getInt(Notification.EXTRA_PROGRESS))
        assertEquals(100, posted.extras.getInt(Notification.EXTRA_PROGRESS_MAX))
    }
}
