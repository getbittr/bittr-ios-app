package com.bittr.android

import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry

/**
 * Runs shell commands as the `shell` user, from inside an instrumented test.
 *
 * `bmgr` is the only way to make the platform produce a real backup set, and it
 * is a shell tool with no Java surface. `UiAutomation.executeShellCommand` runs
 * as uid 2000, which is what holds `android.permission.BACKUP`; the app's own
 * uid does not, so this is not a convenience wrapper around something the test
 * could do directly.
 *
 * Two properties the callers depend on:
 *
 * - **It blocks.** `executeShellCommand` returns a pipe, and reading it to EOF
 *   is what waits for the command to finish. `bmgr backupnow` takes seconds and
 *   a caller that did not wait would assert against the state *before* the
 *   backup. Every call here reads to EOF before returning.
 * - **It does not go through `sh`.** The command is tokenised on whitespace by
 *   the platform, so pipes, globs and quoting do not work. Nothing here needs
 *   them; if something does later, it has to be wrapped in an explicit
 *   `sh -c` and quoted by hand.
 */
internal object DeviceShell {

    fun run(command: String): String {
        val descriptor = InstrumentationRegistry.getInstrumentation()
            .uiAutomation
            .executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { stream ->
            stream.readBytes().toString(Charsets.UTF_8)
        }
    }

    /** `bmgr <arguments>`, with the command echoed into the output for the record. */
    fun bmgr(arguments: String): String = run("bmgr $arguments")
}
