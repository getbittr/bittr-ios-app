package com.bittr.android

import android.content.Context
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.SecureRandom
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

/**
 * **BIT-8 rule 4 / BIT-20 rule 5 — the empirical half. What a real backup set
 * actually contains.**
 *
 * `BackupExclusionRulesTest` reads the manifest and `data_extraction_rules.xml`.
 * `StateDirLocationTest` proves every wallet path resolves under `no_backup`.
 * Both assert *configuration*. Neither can tell you what the platform put in a
 * backup set, and under BIT-20 rule 5 that is not a follow-up question — it is
 * the precondition of `match → keep`. The discriminator proves a state
 * directory is *yours*; it does not prove it is *current*. Same-seed **stale**
 * state signs fine, and publishing a revoked commitment hands the whole channel
 * balance to the counterparty. Foreign state cannot sign, so the case the
 * discriminator does not cover is the worse one, and it is closed at the
 * storage layer or not at all.
 *
 * So this test plants wallet-shaped files, drives `bmgr` to produce a real
 * backup set on both the cloud-backup and the device-transfer path, throws the
 * files away, restores, and asserts none of them came back.
 *
 * ### Why this lives in `:app` and not in `:core:wallet-ldk`
 *
 * BIT-101 asked for it in `:core:wallet-ldk`, next to `WalletPaths`. It cannot
 * usefully go there. A library module's instrumented tests are self-
 * instrumenting: the package under test is `…core.wallet.ldk.test`, whose
 * manifest carries neither `allowBackup="false"` nor `dataExtractionRules`. A
 * test there would produce a backup set for a package configured by default,
 * and prove nothing about the install we ship. `com.bittr.android` is the only
 * package whose backup configuration is the product's, so the test has to run
 * against it.
 *
 * The cost is that the path names below are literals rather than references to
 * `WalletPaths` — `:app` deliberately does not depend on `:core:wallet-ldk`
 * yet, and a test-only dependency would drag the bdk/ldk-node native libraries
 * into the test APK for four strings. `BackupExclusionInstrumentationGuardTest`
 * (JVM, `:app`) fails the build if these literals stop matching `WalletPaths`,
 * so the duplication cannot rot silently.
 *
 * ### Why the canary and the decoys are not padding
 *
 * An empty backup set excludes everything. Absence of wallet material means
 * nothing unless the run can also show that the set was *not* empty, or show
 * that the framework explicitly declined to back this package up. That is what
 * [CANARY] is for: an ordinary file in `files/`, which no rule excludes. If it
 * comes back, the set was real and the wallet material's absence is a result.
 * If it does not, the run has to be able to point at the framework saying so —
 * see [assertNoWalletMaterialSurvives]. Neither branch is allowed to be a
 * silent pass.
 *
 * The two decoys test the `dataExtractionRules` layer on its own terms. Those
 * `<exclude>` entries name `wallet` and `no_backup` in `domain="file"`, whose
 * root is `getFilesDir()` — a *sibling* of `getNoBackupFilesDir()`, not its
 * parent. So the decoys sit where the rules literally point. If a decoy comes
 * back while the wallet markers do not, that is worth knowing and the failure
 * message says exactly what it means: the rules layer is a no-op and the
 * `no_backup` siting is carrying rule 5 alone.
 *
 * ### Status, and the known hazards
 *
 * **Written, never run.** There is no device in the agent container, and no
 * `connectedAndroidTest` step in CI yet — BIT-59. Recording that here rather
 * than letting the file's existence imply a green result. Two things could make
 * the first real run red for reasons that are not a product defect, and both
 * are results to record rather than to design around:
 *
 * 1. **Restoring into a live process.** The instrumentation runs *inside*
 *    `com.bittr.android`, and whether `bmgr restore` kills the target process
 *    is not documented either way. If it does, the run dies mid-class rather
 *    than failing an assertion. The method order below puts the cheap
 *    observations first so their results are already streamed to the host when
 *    that happens.
 * 2. **`is_device_transfer`.** The local transport reads it from
 *    `Settings.Secure.BACKUP_LOCAL_TRANSPORT_PARAMETERS`; it is a test hook,
 *    not API, and [selectLocalTransport] asserts the value was actually taken
 *    rather than assuming it. A rename in a future platform release should fail
 *    loudly here, not quietly turn the device-transfer test into a second cloud
 *    test.
 *
 * If the device-transfer path turns out not to be excludable at all, that is
 * the **halt** recorded in `docs/wallet-security-properties.md` §4 — it goes
 * back to BIT-20 with the result attached, and the guard reverts to iOS
 * behaviour until it is re-decided. It is not a smaller test.
 *
 * Nothing planted here is key material: the blob is a fixed ASCII marker.
 * Never mainnet keys, never real funds.
 */
@RunWith(AndroidJUnit4::class)
// The three methods must run in the order they are written: `backup…` proves
// the machinery is live, and the two that follow are only meaningful if it is.
// NAME_ASCENDING sorts b < c < d, which is why the names begin as they do —
// renaming one without checking that is how the ordering silently inverts.
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class BackupExclusionTest {

    private companion object {
        const val LOCAL_TRANSPORT = "com.android.localtransport/.LocalTransport"

        /** The test hook the local transport reads its operation type from. */
        const val TRANSPORT_PARAMETERS = "backup_local_transport_parameters"

        // Mirrors WalletPaths in :core:wallet-ldk. Kept in step by
        // BackupExclusionInstrumentationGuardTest, which runs on the JVM.
        const val WALLET_DIR = "wallet"
        const val LDK_STATE_DIR = "ldk_state"
        const val QUARANTINE_DIR = "foreign_ldk_state"
        const val SEED_BLOB = "seed.bin"
        const val BDK_DATABASE = "bdk_wallet.sqlite"
        const val DISCRIMINATOR = "seed_discriminator"
        const val LDK_DATABASE = "ldk_node_data.sqlite"

        /** An ordinary file no rule excludes. Its return is what makes the run non-vacuous. */
        const val CANARY = "backup_canary.txt"

        /**
         * The prefix every planted file's contents start with, so the material
         * this class writes is findable by a plain `grep` from outside the
         * process.
         *
         * This class asserts from the inside: plant, back up, delete, restore,
         * assert nothing came back. That is the strong test, and it is also a
         * test whose green depends on `bmgr restore` having worked. A restore
         * that silently did nothing produces "nothing came back" for the wrong
         * reason — the canary assertion below is what catches that, and it
         * catches it only when the framework said `Success`.
         *
         * So `android/scripts/check-backup-set.sh` reads the backup set itself,
         * from the host, after this suite finishes: `adb root`, then grep the
         * local transport's on-disk tree for this prefix. It needs no restore
         * to work and no assertion here to be right — if wallet material is in
         * the set, the bytes are on disk under the transport's directory and
         * the grep finds them. That check exists because it fails independently
         * of everything in this file.
         *
         * **Changing this value without changing it there** turns that grep
         * into one that can never match, i.e. into a permanent silent pass.
         * `android/scripts/test_check_backup_set.sh` reads both files in the
         * `build` job and goes red if they drift.
         */
        const val MARKER_PREFIX = "BIT101-WALLET-MARKER-"
    }

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val packageName: String = context.packageName
    private val random = SecureRandom()

    private var backupWasEnabled: Boolean = false
    private var originalTransport: String = ""
    private var originalParameters: String = ""

    @Before
    fun recordTheDeviceState() {
        backupWasEnabled = "enabled" in DeviceShell.bmgr("enabled").lowercase()
        originalTransport = DeviceShell.bmgr("list transports")
            .lineSequence()
            .firstOrNull { it.trimStart().startsWith("*") }
            ?.trimStart()?.removePrefix("*")?.trim()
            .orEmpty()
        originalParameters = DeviceShell.run("settings get secure $TRANSPORT_PARAMETERS")
            .trim()
            .takeUnless { it == "null" || it.isEmpty() }
            .orEmpty()
    }

    @After
    fun putTheDeviceBack() {
        // Order matters: drop our dataset from the transport before letting go
        // of the transport, or the canary outlives the test on a shared device.
        DeviceShell.bmgr("wipe $LOCAL_TRANSPORT $packageName")
        if (originalParameters.isEmpty()) {
            DeviceShell.run("settings delete secure $TRANSPORT_PARAMETERS")
        } else {
            DeviceShell.run("settings put secure $TRANSPORT_PARAMETERS $originalParameters")
        }
        if (originalTransport.isNotEmpty()) DeviceShell.bmgr("transport $originalTransport")
        if (!backupWasEnabled) DeviceShell.bmgr("enable false")
        removePlantedFiles()
    }

    /**
     * The precondition every other assertion rests on.
     *
     * A device with the backup manager disabled, or without the local
     * transport, produces an empty set for every package — on which the two
     * tests below would pass while proving nothing. This is a test rather than
     * an `Assume` for exactly that reason: a skipped test and a green test look
     * the same in an exit code, and a `connectedAndroidTest` step that runs
     * zero tests exits 0.
     */
    @Test
    fun backupManagerAndTheLocalTransportAreLiveOnThisDevice() {
        if (!backupWasEnabled) DeviceShell.bmgr("enable true")

        val enabled = DeviceShell.bmgr("enabled")
        assertTrue(
            "The backup manager reports \"${enabled.trim()}\" after `bmgr enable true`. " +
                "With it off, every backup set on this device is empty and the two tests " +
                "that follow would pass without the platform having done anything.",
            "enabled" in enabled.lowercase() && "not enabled" !in enabled.lowercase(),
        )

        val transports = DeviceShell.bmgr("list transports")
        assertTrue(
            "This device does not offer $LOCAL_TRANSPORT. Available transports:\n" +
                transports +
                "\nThe local transport is the only one that keeps the set on the device, " +
                "and it is the only one these tests can restore from. A Play-image " +
                "emulator offers the GMS transports instead, which cannot be restored " +
                "from on demand — run this on an AOSP image.",
            LOCAL_TRANSPORT in transports,
        )
    }

    /**
     * The cloud-backup path: `<cloud-backup>` in `data_extraction_rules.xml`,
     * plus `allowBackup="false"`, plus the `no_backup` siting.
     */
    @Test
    fun cloudBackupOfAWalletBearingInstallCarriesNoWalletMaterial() {
        assertNoWalletMaterialSurvives(deviceTransfer = false)
    }

    /**
     * The device-transfer path, which is configured separately from API 31 and
     * is the half `allowBackup="false"` may not cover. This is the run that
     * decides whether `match → keep` is sound; see the class comment.
     */
    @Test
    fun deviceTransferOfAWalletBearingInstallCarriesNoWalletMaterial() {
        assertNoWalletMaterialSurvives(deviceTransfer = true)
    }

    private fun assertNoWalletMaterialSurvives(deviceTransfer: Boolean) {
        val path = if (deviceTransfer) "device-transfer" else "cloud-backup"
        selectLocalTransport(deviceTransfer)

        val markers = plantWalletMaterial() + plantDecoys()
        val canary = File(context.filesDir, CANARY)
            .also { it.parentFile?.mkdirs(); it.writeText(stamp("canary")) }
        val canaryContents = canary.readText()

        val backup = DeviceShell.bmgr("backupnow $packageName")
        val result = resultFor(packageName, backup)

        (markers.map { it.file } + canary).forEach { it.delete() }
        File(context.noBackupFilesDir, WALLET_DIR).deleteRecursively()
        File(context.filesDir, WALLET_DIR).deleteRecursively()

        val restore = restoreLatestSet()
        val canaryReturned = canary.isFile && canary.readText() == canaryContents

        // The record BIT-59's first run should be read against. Printed before
        // the assertions so it survives a failure.
        println(
            "BACKUP_EXCLUSION path=$path api=${Build.VERSION.SDK_INT} package=$packageName " +
                "result=${result ?: "<no result line>"} canaryReturned=$canaryReturned",
        )
        println("BACKUP_EXCLUSION backupnow output:\n$backup")
        println("BACKUP_EXCLUSION restore output:\n$restore")

        for (marker in markers) {
            assertFalse(
                "${marker.what} came back from a $path set: ${marker.file}. " +
                    marker.consequence +
                    "\n\nbmgr backupnow said:\n$backup\nbmgr restore said:\n$restore",
                marker.file.exists(),
            )
        }

        // Only now: was the absence above worth anything?
        val declined = result == null || !result.equals("Success", ignoreCase = true)
        assertTrue(
            "The framework reported \"$result\" for $packageName on the $path path — a " +
                "backup it considers successful — yet the canary written to " +
                "${canary.path} did not come back. This run cannot tell whether the set " +
                "excluded the wallet material or was empty for some unrelated reason, so " +
                "the assertions above prove nothing. Investigate before reading this " +
                "class as green.\n\nbmgr backupnow said:\n$backup\nbmgr restore said:\n" +
                restore,
            canaryReturned || declined,
        )
        if (!canaryReturned) {
            // allowBackup="false" is expected to produce exactly this on the
            // cloud path: the package is never offered to the transport, so
            // nothing of ours is in the set — including the canary. Recorded
            // rather than asserted, because which layer does the work is what
            // the device-transfer run is here to find out.
            println(
                "BACKUP_EXCLUSION $path: the framework declined to back up $packageName " +
                    "(result=${result ?: "<no result line>"}). Exclusion was not exercised " +
                    "on this path; the package was ineligible outright.",
            )
        }
    }

    /**
     * Selects the local transport, in cloud or device-transfer mode.
     *
     * `is_device_transfer` is a test hook on the local transport, read from a
     * secure setting rather than passed to `bmgr`. It is asserted back out of
     * the settings provider because a hook that silently stops existing would
     * turn [deviceTransferOfAWalletBearingInstallCarriesNoWalletMaterial] into
     * a second copy of the cloud test — green, and covering nothing. The
     * transport is re-selected afterwards so it re-reads its parameters.
     */
    private fun selectLocalTransport(deviceTransfer: Boolean) {
        val parameters = "is_device_transfer=$deviceTransfer"
        DeviceShell.run("settings put secure $TRANSPORT_PARAMETERS $parameters")

        val readBack = DeviceShell.run("settings get secure $TRANSPORT_PARAMETERS").trim()
        assertTrue(
            "Wrote \"$parameters\" to secure setting $TRANSPORT_PARAMETERS and read back " +
                "\"$readBack\". The local transport takes its operation type from there; " +
                "without it this is a cloud backup wearing a device-transfer name.",
            readBack == parameters,
        )

        val selected = DeviceShell.bmgr("transport $LOCAL_TRANSPORT")
        assertTrue(
            "Could not select $LOCAL_TRANSPORT: ${selected.trim()}",
            LOCAL_TRANSPORT in selected,
        )
    }

    /** `bmgr list sets` → newest token → `bmgr restore <token> <package>`. */
    private fun restoreLatestSet(): String {
        val sets = DeviceShell.bmgr("list sets")
        val token = Regex("""^\s*([0-9a-fA-F]+)\s*:""", RegexOption.MULTILINE)
            .findAll(sets)
            .map { it.groupValues[1] }
            .lastOrNull()
        val command = if (token != null) "restore $token $packageName" else "restore $packageName"
        return "$ bmgr $command\n(sets: ${sets.trim()})\n${DeviceShell.bmgr(command)}"
    }

    /**
     * A wallet-bearing install, in the shape `WalletPaths` produces.
     *
     * The quarantine subdirectory gets the same `<index>-<random>` name
     * `LdkStateStore` allocates (BIT-20 rule 4 — quarantines never clobber, so
     * their names cannot be fixed). It is here precisely because it is not
     * matchable by a fixed path: an exclusion that only covered the paths this
     * test could name would pass and still leak the one directory holding the
     * state a user needs to sweep a force-closed channel.
     */
    private fun plantWalletMaterial(): List<Marker> {
        val walletDir = File(context.noBackupFilesDir, WALLET_DIR)
        val stateDir = File(walletDir, LDK_STATE_DIR)
        val quarantine = File(File(walletDir, QUARANTINE_DIR), quarantineName())
        stateDir.mkdirs()
        quarantine.mkdirs()

        val stateConsequence =
            "That is ldk-node state on a second device under the same seed. The " +
                "discriminator matches, so the guard keeps it, and stale channel state " +
                "that signs publishes a revoked commitment — the counterparty takes the " +
                "channel balance. See seed-storage-security §5.1."

        return listOf(
            Marker(
                what = "The wrapped seed blob",
                file = File(walletDir, SEED_BLOB),
                consequence = "A wrapped seed off this device is the one artefact BIT-8 " +
                    "rule 4 exists to keep on it. (The blob planted here is a fixed " +
                    "ASCII marker, not key material.)",
            ),
            Marker(
                what = "The ldk-node state database",
                file = File(stateDir, LDK_DATABASE),
                consequence = stateConsequence,
            ),
            Marker(
                what = "The seed discriminator",
                file = File(stateDir, DISCRIMINATOR),
                consequence = "The discriminator is what makes arriving state look like " +
                    "*yours*. Backing it up is what lets stale state pass the guard.",
            ),
            Marker(
                what = "The BDK wallet database",
                file = File(walletDir, BDK_DATABASE),
                consequence = "On-chain descriptors and addresses leave the device with it.",
            ),
            Marker(
                what = "A quarantined ldk-node state file",
                file = File(quarantine, LDK_DATABASE),
                consequence = "$stateConsequence Quarantine names are unique by " +
                    "construction (BIT-20 rule 4), so an exclusion that matched only " +
                    "fixed paths would miss exactly this one.",
            ),
        ).onEach { it.file.writeText(stamp(it.file.name)) }
    }

    /**
     * Where `data_extraction_rules.xml`'s `domain="file"` excludes literally
     * point: under `getFilesDir()`, not under `getNoBackupFilesDir()`.
     */
    private fun plantDecoys(): List<Marker> = listOf(
        Marker(
            what = "The <exclude domain=\"file\" path=\"wallet\"> decoy",
            file = File(File(context.filesDir, WALLET_DIR), "decoy.txt"),
            consequence = "Nothing the product writes lives here — the wallet directory " +
                "is under no_backup. What its return means is that the " +
                "dataExtractionRules layer is a no-op and the no_backup siting is " +
                "carrying BIT-20 rule 5 on its own. Fix the rules; do not relax the rule.",
        ),
        Marker(
            what = "The <exclude domain=\"file\" path=\"no_backup\"> decoy",
            file = File(File(context.filesDir, "no_backup"), "decoy.txt"),
            consequence = "As above. getNoBackupFilesDir() is a sibling of getFilesDir(), " +
                "so this entry never matched the real wallet directory either.",
        ),
    ).onEach { it.file.parentFile?.mkdirs(); it.file.writeText(stamp(it.file.name)) }

    private fun removePlantedFiles() {
        File(context.noBackupFilesDir, WALLET_DIR).deleteRecursively()
        File(context.filesDir, WALLET_DIR).deleteRecursively()
        File(context.filesDir, "no_backup").deleteRecursively()
        File(context.filesDir, CANARY).delete()
    }

    /** `<index>-<8 hex chars>`, the scheme `LdkStateStore.allocateQuarantineDirectory` uses. */
    private fun quarantineName(): String =
        "%04d-%s".format(1, ByteArray(4).also(random::nextBytes).joinToString("") { "%02x".format(it) })

    /**
     * Distinct per file and per run, so a restored file cannot be mistaken for
     * a leftover — and prefixed with [MARKER_PREFIX] so `check-backup-set.sh`
     * can find these bytes in the transport's own tree without a restore.
     */
    private fun stamp(label: String): String =
        MARKER_PREFIX + "$label ${ByteArray(8).also(random::nextBytes).joinToString("") { "%02x".format(it) }}"

    /** The result the framework reported for [target] in `bmgr backupnow` output. */
    private fun resultFor(target: String, output: String): String? =
        Regex("""Package\s+${Regex.escape(target)}\s+with result:\s*(.+)""")
            .find(output)
            ?.groupValues
            ?.get(1)
            ?.trim()

    private data class Marker(val what: String, val file: File, val consequence: String)
}
