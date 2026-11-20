package com.bittr.android

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the lines that keep the wallet out of Recents, as iOS's privacy cover keeps it out of the
 * app switcher. Deleting either leaves every JVM test and every Maestro flow green while the balance
 * is back in Recents, so only a source scan can notice.
 */
class RecentsPrivacyGuardTest {

    private companion object {
        const val ROOT_FILE = "app/src/main/kotlin/com/bittr/android/MainActivity.kt"
    }

    private val rootSource: String by lazy {
        val file = File(SourceTree.root, ROOT_FILE)
        assertTrue("$ROOT_FILE does not exist. If the activity moved, point this guard at its new home.", file.isFile)
        file.readText()
    }

    @Test
    fun `Recents takes no picture of the wallet on Android 13 and up`() {
        assertTrue(
            "$ROOT_FILE no longer calls setRecentsScreenshotEnabled(false), so Recents shows the wallet on Android 13 and up.",
            "setRecentsScreenshotEnabled(false)" in rootSource,
        )
    }

    @Test
    fun `the privacy cover goes up while the app is paused`() {
        assertTrue(
            "$ROOT_FILE no longer draws PrivacyCover, so Recents shows the wallet on Android 8 to 12.",
            "PrivacyCover()" in rootSource,
        )
    }
}
