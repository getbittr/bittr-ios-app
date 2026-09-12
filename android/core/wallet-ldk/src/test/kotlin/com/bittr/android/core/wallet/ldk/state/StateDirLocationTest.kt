package com.bittr.android.core.wallet.ldk.state

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * **BIT-20 rule 5, layer 3 — every wallet file resolves under `no_backup`.**
 *
 * Siting is the layer that a future pull request cannot weaken by accident.
 * `allowBackup="false"` and `dataExtractionRules` are manifest state, and
 * manifest state is one attribute away from being undone; a path is not. This
 * is the direct analogue of iOS's per-file `excludeFromBackup()`
 * (`LightningStorage.swift:38–43`), which exists precisely because the
 * directory-level flag was not enough on its own.
 *
 * The same assertion doubles as the `afterFirstUnlock` check.
 * `getNoBackupFilesDir()` is `<CE-data-dir>/no_backup`, and credential-
 * encrypted storage is unreadable until the first unlock after boot. That is
 * what buys back the half of the iOS accessibility class a non-auth-bound
 * Keystore key does not give us on its own — a non-auth-bound key is usable
 * during Direct Boot. Assert the CE data dir here, and
 * `WalletKeystorePolicyGuardTest` bans the one call that would move it.
 *
 * Pinned to 26 / 34 / 36 rather than left to default, for the reason in
 * `AndroidKeystoreBlobCodec`'s neighbours: the security statement this test
 * backs is written *per API level*, so the levels have to be in the source
 * rather than inherited from whatever `compileSdk` happens to be. 26 is
 * `minSdk` — the floor the claim has to hold at; 34 is what the CI emulator
 * boots, so the JVM row and the instrumented row agree; 36 is the newest
 * Robolectric 4.16.1 can instantiate. Leaving it unpinned silently followed
 * `compileSdk` to 37 and the whole class stopped running.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [26, 34, 36])
class StateDirLocationTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `every wallet path is under the no-backup directory`() {
        val paths = WalletPaths.forContext(context)
        val noBackup = context.noBackupFilesDir.canonicalFile

        val everyPath = mapOf(
            "wallet directory" to paths.walletDir,
            "ldk-node state directory" to paths.ldkStateDir,
            "BDK database" to paths.bdkDatabaseFile,
            "wrapped seed blob" to paths.seedBlobFile,
            "quarantine root" to paths.quarantineRoot,
            "seed discriminator" to paths.discriminatorFile,
        )

        for ((what, path) in everyPath) {
            assertTrue(
                "The $what resolves to $path, which is not under $noBackup. Anything " +
                    "outside no_backup can reach a cloud backup or a device transfer, " +
                    "and same-seed stale channel state that signs is worse than foreign " +
                    "state that cannot — see seed-storage-security §5.1.",
                path.canonicalFile.startsWith(noBackup),
            )
        }
    }

    @Test
    fun `the no-backup directory is inside credential-encrypted storage`() {
        val noBackup = context.noBackupFilesDir.canonicalFile
        val deviceProtected = context.createDeviceProtectedStorageContext()
            .noBackupFilesDir.canonicalFile

        assertTrue(
            "no_backup must sit under the app's data dir, which is credential-" +
                "encrypted by default. That is what reproduces iOS's " +
                "afterFirstUnlockThisDeviceOnly: unreadable until the first unlock " +
                "after boot.",
            noBackup.path.contains("/no_backup"),
        )
        // The point of the comparison: the device-encrypted variant is a
        // *different* directory and it is readable pre-unlock. Landing there
        // would silently downgrade the seed blob's at-rest class below iOS's,
        // with every other test in this module still green.
        assertTrue(
            "Expected the CE and DE no_backup directories to differ; if they do not, " +
                "this Robolectric configuration cannot tell the two apart and the " +
                "assertion above is not proving what it claims.",
            noBackup != deviceProtected,
        )
    }

    @Test
    fun `the discriminator lives inside the state directory it describes`() {
        val paths = WalletPaths.forContext(context)

        assertEquals(
            "The discriminator must travel with the state or not at all. A state " +
                "directory that arrives without it reads as `absent`, which is the " +
                "fail-safe row.",
            paths.ldkStateDir.canonicalFile,
            paths.discriminatorFile.canonicalFile.parentFile,
        )
    }

    @Test
    fun `quarantines inherit the exclusion from their parent`() {
        val paths = WalletPaths(File(context.noBackupFilesDir, "fixture"))
        paths.createDirectories()
        seedStateFile(paths)

        val quarantine = LdkStateStore(paths).quarantineLightningState()!!

        assertTrue(
            "Each new quarantine subdirectory must inherit the exclusion from " +
                "no_backup without a per-directory call. iOS has to re-exclude " +
                "explicitly (LightningStorage.swift:99–105) because its exclusion is " +
                "per-file and the quarantine name does not match the state prefix.",
            quarantine.canonicalFile.startsWith(context.noBackupFilesDir.canonicalFile),
        )
    }

    private fun seedStateFile(paths: WalletPaths) {
        File(paths.ldkStateDir, "ldk_node_data.sqlite").writeText("state")
    }
}
