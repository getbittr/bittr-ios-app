package com.bittr.android

import com.bittr.android.SourceTree.repoPath
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Keeps `FLAG_SECURE` from blanking the entire screenshot suite.
 *
 * `FLAG_SECURE` is Android's answer to the seed-phrase screenshot warning that iOS
 * implements with `userDidTakeScreenshotNotification` (DEV-18,
 * `shared/docs/parity.md` → *Deliberate platform divergences*). It is the right
 * answer. It is also a **window** flag, and this app has exactly one window —
 * single Activity, Compose Navigation. Two consequences:
 *
 * 1. A `FLAG_SECURE` window is captured as a black frame by `adb screencap`, which
 *    is what Maestro's `takeScreenshot` drives. Screenshots do not fail, they come
 *    out blank — so this failure passes CI and is only caught by someone opening
 *    the artefacts.
 * 2. Set once in `MainActivity.onCreate`, it stays set for the whole session. That
 *    is not "the mnemonic screen is protected", it is all 329 `takeScreenshot`
 *    steps returning black.
 *
 * So the flag must be scoped to the screen that needs it and cleared on the way
 * out — a `DisposableEffect` that adds it on enter and clears it on dispose — never
 * set app-wide. This test enforces the "never app-wide" half; the scoped use is
 * allowed anywhere else.
 */
class ScreenshotBlockingGuardTest {

    private companion object {
        val SECURE_FLAG_SYMBOLS = listOf("FLAG_SECURE", "setRecentsScreenshotEnabled")

        /** Files whose scope is the whole app session, so a flag set here never comes off. */
        val APP_WIDE_FILES = setOf("MainActivity.kt", "BittrApplication.kt")
    }

    @Test
    fun `FLAG_SECURE is never set app-wide`() {
        val offenders = SourceTree.kotlinSources("ScreenshotBlockingGuardTest.kt")
            .filter { it.name in APP_WIDE_FILES }
            .mapNotNull { file ->
                val text = file.readText()
                val hit = SECURE_FLAG_SYMBOLS.firstOrNull { it in text } ?: return@mapNotNull null
                "${file.repoPath()} (sets $hit)"
            }

        assertTrue(
            "FLAG_SECURE must be scoped to the screen that needs it (add on enter, clear on " +
                "dispose), never set on the Activity or Application. This is a single-window " +
                "app, so an app-wide FLAG_SECURE makes every Maestro takeScreenshot capture a " +
                "black frame — all 329 of them — without failing a single flow.\n" +
                "Offending files:\n  " + offenders.joinToString("\n  "),
            offenders.isEmpty(),
        )
    }
}
