package com.bittr.android.core.wallet.ldk.seed

import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry

/**
 * Runs shell commands as the `shell` user, from inside an instrumented test.
 *
 * A near-twin of `:app`'s `DeviceShell` and deliberately a second copy rather
 * than a shared fixture: `androidTest` source sets are not visible across
 * modules, and the alternative — a `testFixtures` publication just for this —
 * would put a nine-line object behind a build-graph change. The two are expected
 * to drift, because they wrap different tools for different reasons.
 *
 * Here the tool is `locksettings`, which sets and clears the device's lock-screen
 * credential. It has no Java surface at all, and the app's own uid could not call
 * it if it had one: mutating the lock screen is a `shell` (uid 2000) privilege.
 * That is the whole reason [SeedReadableWhileLockedTest] can ask its question
 * from inside one instrumentation run, where BIT-18's K1 needed a host driver —
 * K1 mutates the credential *between* two runs and has to survive the process
 * dying in between; this one only needs the device locked *during* one read.
 *
 * Two properties the callers depend on, both inherited from `DeviceShell`:
 *
 * - **It blocks.** `executeShellCommand` returns a pipe and reading it to EOF is
 *   what waits for the command to finish. `locksettings set-pin` returning
 *   before the credential exists would have the test assert against the state
 *   before the lock.
 * - **It does not go through `sh`.** The command is tokenised on whitespace by
 *   the platform, so quoting, pipes and globs do not work. Nothing here needs
 *   them.
 */
internal object WalletDeviceShell {

    fun run(command: String): String {
        val descriptor = InstrumentationRegistry.getInstrumentation()
            .uiAutomation
            .executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { stream ->
            stream.readBytes().toString(Charsets.UTF_8)
        }
    }
}
