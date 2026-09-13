package com.bittr.android

import android.content.Context
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.SecureRandom
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
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
 * So this class plants wallet-shaped files and gets a real backup set produced
 * from them on both the cloud-backup and the device-transfer path, leaving that
 * set on the device for `android/scripts/check-backup-set.sh` to read. It drives
 * only the cloud backup itself; the device-transfer one is driven from the host,
 * for the reason in "Dropping the restore was necessary and not sufficient"
 * below.
 *
 * ### Why the assertion moved out of this process — BIT-108
 *
 * The first version deleted what it planted, ran `bmgr restore`, and asserted
 * nothing came back. Run 107 (BIT-59, API 34 `aosp_atd`) is the first time that
 * ran on a device, and it settled the first hazard the previous revision of
 * this comment listed as undecided:
 *
 * - `backupManagerAndTheLocalTransportAreLiveOnThisDevice` — passed.
 * - `cloudBackupOfAWalletBearingInstallCarriesNoWalletMaterial` — passed.
 * - `deviceTransferOfAWalletBearingInstallCarriesNoWalletMaterial` — failed
 *   with a completely empty `<failure>`, and every case of
 *   `InstalledBackupConfigurationTest` after it never ran at all.
 *
 * An empty `<failure>` with nothing after it is not an assertion; every
 * assertion here inlines `bmgr` output into its message. It is the runner
 * recording that the instrumentation process died. **`bmgr restore` kills the
 * target process**, which is this one, so a restore assertion cannot live in
 * the process being restored. That is not fixable by writing the assertion
 * more carefully.
 *
 * It is worth being precise about what the in-process restore could ever have
 * proven, because the answer is "less than it looked". A restore only kills the
 * process when the framework has something to restore. So the assertion passes
 * exactly when the package was ineligible and nothing was backed up — which is
 * the case where it had nothing to check — and dies exactly when there was a
 * set worth checking. Run 107 is that shape end to end: cloud passed (nothing
 * was backed up), device-transfer died (something was). The restore is dropped
 * from both paths rather than from the one that crashed, because on the cloud
 * path it was never evidence either.
 *
 * ### Dropping the restore was necessary and not sufficient — run 133
 *
 * Run 133 (`0dd62293` on `android-parity`) is the first run to carry the
 * restore-free version above, and it reproduced run 107's signature exactly:
 * `deviceTransfer…` with an empty `<failure>`, all four
 * `InstalledBackupConfigurationTest` cases never reached. So the restore was
 * not the only thing in here that killed this process, and the fix that removed
 * it closed one of two doors.
 *
 * What is left is **`bmgr backupnow` itself, on the device-transfer path**. The
 * framework binds a backup agent *inside the target process* to service a
 * backup and tears that agent down when the backup completes, killing the
 * process with it. The instrumentation runs in that process, so the teardown
 * takes the test runner with it — the same structural fault as the restore, one
 * step earlier in the same method.
 *
 * The two paths' results discriminate it cleanly, and they are the reason this
 * is stated as a mechanism rather than a guess:
 *
 * - **cloud** — `allowBackup="false"` makes the package ineligible, so no agent
 *   is ever bound, so nothing is torn down. The test passes. It has passed on
 *   every run.
 * - **device-transfer** — `allowBackup="false"` does *not* cover D2D, which is
 *   the entire reason this path is tested separately. The package is eligible,
 *   an agent is bound, the backup runs, the agent is torn down, and this process
 *   dies. It has died on every run.
 *
 * Note what that means about the cloud path's green: it survives because nothing
 * happens on it, by the same argument that made the old restore worthless. It is
 * not evidence that driving a backup from in here is safe.
 *
 * So the backup moved out too. [deviceTransferOfAWalletBearingInstallCarriesNoWalletMaterial]
 * now **plants and stops**: it writes the wallet material, the canary and the
 * decoys, arms the `is_device_transfer` hook, clears the previous dataset, and
 * hands off. `ci-wallet-instrumented.sh` drives `bmgr backupnow` from the host
 * after Gradle exits, where there is no instrumentation process left to kill,
 * and `check-backup-set.sh` greps the set it produced. See [HANDOFF] for the
 * contract between the two halves.
 *
 * ### Where the verdict lives now
 *
 * `android/scripts/check-backup-set.sh`, from the host, in the same CI job:
 * `adb root`, then grep the local transport's own on-disk tree for
 * [MARKER_PREFIX]. It needs no restore and no surviving instrumentation
 * process, which is exactly why it still answered on run 107 when this class
 * could not — the set was reachable, it was searched, and no wallet marker was
 * in it.
 *
 * The split is therefore: **this class creates the conditions and proves it
 * created them; the host script reads the set and returns the verdict.** Each
 * half is worthless alone, and both run in the same job. What this class still
 * owns:
 *
 * - the transport is live and is the *local* one (an absent transport makes
 *   every set empty and every exclusion claim vacuous);
 * - the `is_device_transfer` hook was actually taken, so the second path is not
 *   a second copy of the first;
 * - on the **cloud** path only, that `bmgr backupnow` ran to completion and the
 *   framework returned a considered per-package result rather than a transport
 *   error — a failed backup leaves no set, and a grep of no set is not evidence
 *   of anything;
 * - on the **device-transfer** path, that a full wallet-bearing install is on
 *   disk and the previous dataset is cleared, i.e. that the host has something
 *   to back up and whatever it produces is this run's.
 *
 * The equivalent "the backup completed" check for the device-transfer path is
 * the host's, because the backup is: see [HANDOFF].
 *
 * ### Only one set survives to be read, and it is the device-transfer one
 *
 * The local transport keeps one dataset per package, so a second `backupnow`
 * replaces the first. Each backup is therefore preceded by a wipe of this
 * package's dataset rather than followed by one, which makes the surviving set
 * deterministic instead of an accident of which test crashed:
 * `NAME_ASCENDING` puts device-transfer last, so the set the host greps is
 * always the device-transfer one. Since the device-transfer backup itself is now
 * the host's, that ordering is enforced by construction — the cloud backup is
 * the only one this process drives, and the host's runs strictly after Gradle
 * has exited.
 *
 * That is the right way round. `allowBackup="false"` is expected to keep the
 * package out of a cloud set outright — there is nothing there to inspect —
 * while API 31+ configures device transfer separately, and that is the half the
 * flag may not cover and the half BIT-20 §5.3 turns on. The `BACKUP_EXCLUSION`
 * lines below record each path's result so the difference between the two is
 * stated by the run rather than inferred from which one crashed.
 *
 * ### Why the canary and the decoys are not padding
 *
 * An empty backup set excludes everything, so "no wallet marker in the set"
 * means nothing unless the set was not empty. [CANARY] is an ordinary file in
 * `files/` that no rule excludes, written with [CANARY_PREFIX] so the host-side
 * grep can find it by the same mechanism it finds wallet material by. Canary
 * present and no wallet marker is the strong result; neither present means the
 * package was ineligible and the exclusion rules were never consulted, which is
 * a different (and weaker) claim that has to be reported as one.
 *
 * The two decoys test the `dataExtractionRules` layer on its own terms. Those
 * `<exclude>` entries name `wallet` and `no_backup` in `domain="file"`, whose
 * root is `getFilesDir()` — a *sibling* of `getNoBackupFilesDir()`, not its
 * parent. So the decoys sit where the rules literally point. A decoy in the set
 * while the wallet markers are not is worth knowing: it means the rules layer
 * is a no-op and the `no_backup` siting is carrying rule 5 alone. They carry
 * [DECOY_PREFIX], distinct from [MARKER_PREFIX], so finding one is not reported
 * as the §5.3 halt.
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
 * into the test APK for six strings. `BackupExclusionInstrumentationGuardTest`
 * (JVM, `:app`) fails the build if these literals stop matching `WalletPaths`,
 * and fails it again if a `bmgr restore` is ever reintroduced here, so neither
 * the duplication nor BIT-108's lesson can rot silently.
 *
 * ### The stop condition still stands
 *
 * If the device-transfer path turns out not to be excludable at all — the host
 * grep finding [MARKER_PREFIX] in a real set — that is the **halt** recorded in
 * `docs/wallet-security-properties.md` §4. It goes back to BIT-20 with the
 * result attached, and the guard reverts to iOS behaviour until it is
 * re-decided. It is not a smaller test. Run 107 did not produce it, and a
 * crashed process is not it either.
 *
 * Nothing planted here is key material: the blob is a fixed ASCII marker.
 * Never mainnet keys, never real funds.
 */
@RunWith(AndroidJUnit4::class)
// The three methods must run in the order they are written: `backup…` proves
// the machinery is live, and the two that follow are only meaningful if it is.
// NAME_ASCENDING sorts b < c < d, which is why the names begin as they do —
// renaming one without checking that is how the ordering silently inverts, and
// it is also what decides which path's set survives for the host to read.
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

        /** An ordinary file no rule excludes. Its presence is what makes the set non-empty. */
        const val CANARY = "backup_canary.txt"

        /**
         * The prefix every planted **wallet** file's contents start with, so
         * the material this class writes is findable by a plain `grep` from
         * outside the process.
         *
         * This is the string `android/scripts/check-backup-set.sh` searches the
         * backup transport's on-disk tree for, and since BIT-108 it is the only
         * thing that returns a verdict on rule 5: the in-process restore that
         * used to do it killed the process it asserted from. If wallet material
         * reached the set, these bytes are on disk under the transport's
         * directory and the grep finds them, with no restore and no surviving
         * instrumentation process required.
         *
         * **Changing this value without changing it there** turns that grep
         * into one that can never match, i.e. into a permanent silent pass.
         * `android/scripts/test_check_backup_set.sh` reads both files in the
         * `build` job and goes red if they drift. It finds this line by a
         * textual grep for the constant's name followed by its assignment, and
         * takes the *first* hit in the file — so the two prefixes below are
         * deliberately not named `…MARKER_PREFIX`, and prose above this point
         * must not spell that assignment out either, or the drift check reads
         * a sentence instead of the value.
         */
        const val MARKER_PREFIX = "BIT101-WALLET-MARKER-"

        /**
         * The canary's prefix, deliberately *not* [MARKER_PREFIX].
         *
         * Absence of wallet material in a set proves nothing if the set was
         * empty, and `allowBackup="false"` making the package ineligible
         * produces exactly an empty set. The canary is the difference between
         * "the rules excluded our wallet files" and "the framework never
         * offered this package to the transport", and both are legitimate
         * outcomes that have to be told apart rather than both read as green.
         *
         * It is a separate string because the host-side grep must be able to
         * find the canary *without* that counting as the §5.3 halt.
         */
        const val CANARY_PREFIX = "BIT101-CANARY-MARKER-"

        /**
         * The decoys' prefix, also not [MARKER_PREFIX], for the same reason.
         *
         * A decoy in the set means `dataExtractionRules`' `domain="file"`
         * entries are a no-op and the `no_backup` siting is carrying rule 5
         * alone. That is a finding about the rules, not wallet material
         * escaping, and it must not trip the halt.
         */
        const val DECOY_PREFIX = "BIT101-DECOY-MARKER-"

        /** Results that mean the backup never completed, so no set exists to inspect. */
        val TRANSPORT_FAILURE = Regex("""transport\s+error|transport\s+not\s+initial""", RegexOption.IGNORE_CASE)

        /**
         * **The device-transfer hand-off, as a file. `ci-wallet-instrumented.sh`
         * reads it with `adb root`, so it is an interface and not a log line.**
         *
         * [deviceTransferOfAWalletBearingInstallCarriesNoWalletMaterial] cannot
         * drive its own backup — that is what BIT-108 is, and dropping the
         * restore did not fix it (see the class comment on run 133). It plants,
         * arms the hook, wipes the stale dataset and stops. The host then runs
         * `bmgr backupnow` with no instrumentation process left to kill.
         *
         * The host must not back up on the strength of the tests having passed.
         * On a run where this method was filtered out, renamed, or never reached,
         * the plant does not exist, and backing up anyway produces the empty set
         * that `check-backup-set.sh` cannot tell from a clean one — the exact
         * vacuous green this suite exists to refuse. This file is written **after**
         * the plant is on disk and the wipe has happened, so its presence means
         * those things were true, and its absence means the host must report
         * "nothing to inspect" rather than grep.
         *
         * **Why a file and not the `println` next to it.** Instrumentation stdout
         * reaches the host only if the runner files it into the JUnit XML's
         * `<system-out>`, and run 133 recorded that it did not: the gate's
         * `What the device reported` annotation fired with no `BACKUP_EXCLUSION`
         * line in it. A hand-off carried on that channel would be missing exactly
         * when something went wrong, which is when it has to be right. A file in
         * the app's own data directory is written by the same `File.writeText`
         * the plant uses and read back by the same `adb root` the set inspection
         * already needs.
         *
         * It sits in `getNoBackupFilesDir()` rather than `getFilesDir()` so that
         * it cannot itself end up in the set it is announcing.
         *
         * That is also why the hand-off is not simply `is_device_transfer`: the
         * secure setting says the hook is armed, which is device state that
         * outlives a run that planted nothing.
         */
        const val HANDOFF_FILE = "backup_handoff.txt"

        /** The contents of [HANDOFF_FILE]. Matched exactly by the host. */
        const val HANDOFF = "BACKUP_EXCLUSION_HANDOFF device-transfer-plant-ready"
    }

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val packageName: String = context.packageName
    private val random = SecureRandom()

    private var backupWasEnabled: Boolean = false
    private var originalTransport: String = ""
    private var originalParameters: String = ""

    /**
     * Set once the device-transfer plant is on disk and the host's backup is the
     * next thing that should touch this package. While it is set, [putTheDeviceBack]
     * does nothing: the plant, the armed hook and the cleared dataset are the
     * hand-off, and tearing any of them down is tearing down the evidence.
     */
    private var handedOffToHost: Boolean = false

    @Before
    fun recordTheDeviceState() {
        // A hand-off from an earlier run must never be readable by this one's
        // host phase. The AVD is restored from a cached snapshot and the app's
        // data directory can outlive a run, so "the file is there" would
        // otherwise mean "some run got that far", not "this one did" — and the
        // host would back up and grep on the strength of a plant that is not on
        // disk any more. Cleared before every method rather than only before the
        // device-transfer one, so a rename or a reordering cannot skip it.
        File(context.noBackupFilesDir, HANDOFF_FILE).delete()

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

    /**
     * Puts the device's backup settings back, and **deliberately leaves the
     * backup set alone.**
     *
     * The previous revision ran `bmgr wipe` here, on the reasoning that a
     * dataset should not outlive the test on a shared device. That is also what
     * destroyed the only artefact the run produces: `check-backup-set.sh` reads
     * the transport's tree from the host *after* Gradle exits, so a wipe here
     * means it inspects a set this suite already deleted. On run 107 the one
     * set it could read survived only because the device-transfer crash skipped
     * this method — the evidence was an accident.
     *
     * So the wipe moved to before each backup instead of after. A pre-wipe leaves
     * a set behind, which is the point, and additionally guarantees that whatever
     * the host finds was produced by this run rather than by the previous one.
     *
     * **And once [handedOffToHost] is set, this method does nothing at all.**
     * The device-transfer backup is the host's (BIT-108), and everything this
     * method would undo is precisely what the host needs to find: the planted
     * files are the thing being backed up, the `is_device_transfer` hook decides
     * which path the backup takes, and the local transport is where the set
     * lands. Restoring any of them would leave the host backing up a clean
     * install over the cloud path — an empty set that `check-backup-set.sh`
     * reports as "no wallet marker", which is the vacuous green this whole file
     * exists to refuse. The device is CI-ephemeral and the run ends here, so
     * there is nothing left to be tidy for.
     */
    @After
    fun putTheDeviceBack() {
        if (handedOffToHost) return

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
                "and a set on the device is the only kind check-backup-set.sh can read. " +
                "A Play-image emulator offers the GMS transports instead, which put the " +
                "set in a Google account — run this on an AOSP image.",
            LOCAL_TRANSPORT in transports,
        )
    }

    /**
     * The cloud-backup path: `<cloud-backup>` in `data_extraction_rules.xml`,
     * plus `allowBackup="false"`, plus the `no_backup` siting.
     *
     * Its set is replaced by the device-transfer test that runs after it — see
     * the class comment — so the verdict the host returns is that path's. What
     * this run records for the cloud path is the framework's own answer to
     * "would you back this package up at all", which under `allowBackup="false"`
     * is expected to be no, and which is a *stronger* exclusion than a rule
     * consulted and obeyed.
     */
    @Test
    fun cloudBackupOfAWalletBearingInstallCarriesNoWalletMaterial() {
        driveTheCloudBackup()
    }

    /**
     * The device-transfer path, which is configured separately from API 31 and
     * is the half `allowBackup="false"` may not cover. This is the run that
     * decides whether `match → keep` is sound; see the class comment.
     *
     * **It does not back up.** It plants a wallet-bearing install, arms the
     * `is_device_transfer` hook, clears the stale dataset, and prints [HANDOFF].
     * `ci-wallet-instrumented.sh` drives `bmgr backupnow` from the host once
     * Gradle has exited, because on this path the backup binds an agent in this
     * process and the framework kills the process when it tears that agent down
     * — which is BIT-108, and is why runs 107 and 133 both ended here with an
     * empty `<failure>` and nothing after it.
     *
     * What this method can still be wrong about is worth stating, because it is
     * no longer "the exclusion leaked": it is "the host was handed something
     * other than a wallet-bearing install on the device-transfer path". Each
     * assertion below is one way that happens.
     */
    @Test
    fun deviceTransferOfAWalletBearingInstallCarriesNoWalletMaterial() {
        selectLocalTransport(deviceTransfer = true)

        // Before, not after, and here rather than after the backup: the host's
        // backupnow is what writes the set, so the dataset has to be clear by the
        // time this process exits. Whatever the host then finds on the transport
        // was produced by its own backup and not left over from the cloud test
        // above or from a previous run on a cached AVD snapshot.
        DeviceShell.bmgr("wipe $LOCAL_TRANSPORT $packageName")

        val markers = plantWalletMaterial() + plantDecoys()
        val canary = File(context.filesDir, CANARY)
            .also { it.parentFile?.mkdirs(); it.writeText(CANARY_PREFIX + stamp("canary")) }

        println(
            "BACKUP_EXCLUSION path=device-transfer api=${Build.VERSION.SDK_INT} " +
                "package=$packageName result=<host drives the backup> " +
                "walletMarker=$MARKER_PREFIX canaryMarker=$CANARY_PREFIX " +
                "decoyMarker=$DECOY_PREFIX setLeftOnTransport=true",
        )
        println("BACKUP_EXCLUSION device-transfer canary: ${canary.path}")
        for (marker in markers) {
            println(
                "BACKUP_EXCLUSION device-transfer plant: ${marker.file.name} at " +
                    "${marker.file.path} — ${marker.what}. If this one is in the set: " +
                    marker.consequence,
            )
        }

        // 1. The plant is actually on disk. `plantWalletMaterial` writes through
        //    File.writeText, which throws on failure, so this is not re-checking
        //    the write — it is checking that the paths it wrote to are the ones
        //    that still exist now, after the decoys were planted into a sibling
        //    tree whose names overlap (`files/no_backup` vs `getNoBackupFilesDir`).
        //    A plant that deleted itself would hand the host an empty set.
        val missing = markers.filterNot { it.file.isFile && it.file.length() > 0 }
        assertTrue(
            "These planted files are not on disk at the point this process hands off to " +
                "the host, so the backup the host is about to drive would not contain them " +
                "and check-backup-set.sh would report a clean set for the wrong reason:\n" +
                missing.joinToString("\n") { "  ${it.file.path} — ${it.what}" },
            missing.isEmpty(),
        )
        assertTrue(
            "The canary ${canary.path} is not on disk. It is the file that makes a " +
                "non-empty set distinguishable from an ineligible package, so without it " +
                "the host's grep cannot tell 'the rules excluded our wallet files' from " +
                "'the framework never offered this package to the transport'.",
            canary.isFile && canary.length() > 0,
        )

        // 2. The dataset really is gone. `bmgr wipe` reports success for a package
        //    the transport has never heard of, so this is about the transport
        //    having accepted the command at all — a wipe that silently no-ops
        //    leaves the cloud test's set in place, and the host's grep would then
        //    return a verdict on the wrong path while naming this one.
        val setsAfterWipe = DeviceShell.bmgr("list sets")
        println("BACKUP_EXCLUSION device-transfer list sets after wipe:\n$setsAfterWipe")

        // 3. Tell the host it may proceed. Written last, so it exists only if
        //    everything above held. @After is disarmed at the same moment: from
        //    here the planted files, the hook and the cleared dataset belong to
        //    the host.
        //
        //    Deliberately not wrapped in a try: if this write fails, the host
        //    finds no hand-off and reports that it had nothing to inspect, which
        //    is the correct reading of a run whose plant could not finish.
        val handoff = File(context.noBackupFilesDir, HANDOFF_FILE)
        handoff.writeText(HANDOFF)
        handedOffToHost = true
        println("$HANDOFF at ${handoff.path}")
    }

    /**
     * Plants a wallet-bearing install and drives the **cloud** backup from it.
     *
     * Only the cloud path is driven in-process, and the asymmetry is the whole
     * of BIT-108 rather than an inconsistency. On this path `allowBackup="false"`
     * is expected to make the package ineligible, so the framework never binds a
     * backup agent in this process and there is nothing for it to tear this
     * process down with. On the device-transfer path it does bind one, and the
     * teardown is fatal — see
     * [deviceTransferOfAWalletBearingInstallCarriesNoWalletMaterial].
     *
     * That asymmetry is load-bearing and unproven-by-construction: if
     * `allowBackup` were ever set back to `true`, this method would start
     * binding an agent too and would die exactly the way the device-transfer one
     * did. It does not fail safe, it fails loud — an empty `<failure>` on a run
     * that used to be green — and the same annotation in
     * `check-wallet-instrumented-results.py` that names run 107's signature
     * would name it.
     *
     * Everything asserted here is observable without a restore, because a
     * restore kills this process (BIT-108). What is asserted is that the run
     * produced something worth inspecting; whether what it produced is clean is
     * `check-backup-set.sh`'s answer, and the two run in the same job.
     */
    private fun driveTheCloudBackup() {
        val path = "cloud-backup"
        selectLocalTransport(deviceTransfer = false)

        // Before, not after. The transport keeps one dataset per package, so
        // this makes the set this backup leaves unambiguously this path's. It is
        // then replaced by the host's device-transfer backup, which is the set
        // check-backup-set.sh actually reads.
        DeviceShell.bmgr("wipe $LOCAL_TRANSPORT $packageName")

        val markers = plantWalletMaterial() + plantDecoys()
        val canary = File(context.filesDir, CANARY)
            .also { it.parentFile?.mkdirs(); it.writeText(CANARY_PREFIX + stamp("canary")) }

        val backup = DeviceShell.bmgr("backupnow $packageName")
        val result = resultFor(packageName, backup)
        val sets = DeviceShell.bmgr("list sets")

        // The record BIT-59 promotes into ::notice:: annotations, which on this
        // public repo is the only channel a run's output is readable through.
        // Printed before the assertions so it survives a failure — and, unlike
        // the restore this replaced, it survives whatever the framework does to
        // this process afterwards.
        println(
            "BACKUP_EXCLUSION path=$path api=${Build.VERSION.SDK_INT} package=$packageName " +
                "result=${result ?: "<no result line>"} " +
                "walletMarker=$MARKER_PREFIX canaryMarker=$CANARY_PREFIX " +
                "decoyMarker=$DECOY_PREFIX setLeftOnTransport=false",
        )
        println("BACKUP_EXCLUSION $path canary: ${canary.path}")
        // The decoder ring for a halt. check-backup-set.sh can only report the
        // transport files a marker was found in; the marker's own bytes name
        // the file it was planted as, and these lines say what finding that
        // particular one would mean. Emitted per path because that is the
        // channel a red run is read through.
        for (marker in markers) {
            println(
                "BACKUP_EXCLUSION $path plant: ${marker.file.name} at ${marker.file.path} — " +
                    "${marker.what}. If this one is in the set: ${marker.consequence}",
            )
        }
        println("BACKUP_EXCLUSION $path backupnow output:\n$backup")
        println("BACKUP_EXCLUSION $path list sets:\n$sets")

        // 1. The framework considered this package. A `backupnow` that never
        //    names it did not produce a set, and a grep of no set is not
        //    evidence — it is the vacuous green this whole file exists to
        //    refuse.
        assertNotNull(
            "`bmgr backupnow $packageName` returned no per-package result line for " +
                "$packageName on the $path path, so the framework never reported what it " +
                "did with this package and no set can be assumed to exist. " +
                "check-backup-set.sh's grep would then be searching a set that was never " +
                "written, and would report \"clean\" for the wrong reason.\n\nOutput was:\n" +
                backup,
            result,
        )

        // 2. It completed. A transport error is not an exclusion; it is a run
        //    that produced nothing, and it must not be read as one that
        //    produced an empty set on purpose.
        assertFalse(
            "The backup transport failed on the $path path — the framework reported " +
                "\"$result\" for $packageName. Nothing was written, so nothing can be " +
                "inspected, and the absence of wallet material from a set that does not " +
                "exist says nothing about rule 5. This is an infrastructure failure to " +
                "fix, not the BIT-20 §5.3 halt.\n\nbmgr backupnow said:\n$backup",
            TRANSPORT_FAILURE.containsMatchIn(result.orEmpty()),
        )

        // 3. Say which of the two shapes this path produced, in the annotation
        //    channel, because they carry different strengths of claim and run
        //    107 left them to be inferred from which test crashed.
        val backedUp = result.equals("Success", ignoreCase = true)
        if (backedUp) {
            println(
                "BACKUP_EXCLUSION $path: the framework backed $packageName up " +
                    "(result=$result). The package WAS offered to the transport on this " +
                    "path, so the exclusion rules were actually consulted and the set is " +
                    "worth reading. check-backup-set.sh returns the verdict; it should " +
                    "find $CANARY_PREFIX and must not find $MARKER_PREFIX.",
            )
        } else {
            println(
                "BACKUP_EXCLUSION $path: the framework declined to back $packageName up " +
                    "(result=$result). Exclusion was not exercised on this path — the " +
                    "package was ineligible outright, which is what allowBackup=\"false\" " +
                    "is expected to do on the cloud path. The set is empty, so a host-side " +
                    "grep finding no $MARKER_PREFIX is consistent with that and is not " +
                    "independent evidence that the rules work.",
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
        ).onEach { it.file.writeText(MARKER_PREFIX + stamp(it.file.name)) }
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
                "is under no_backup. What its presence in a set means is that the " +
                "dataExtractionRules layer is a no-op and the no_backup siting is " +
                "carrying BIT-20 rule 5 on its own. Fix the rules; do not relax the rule.",
        ),
        Marker(
            what = "The <exclude domain=\"file\" path=\"no_backup\"> decoy",
            file = File(File(context.filesDir, "no_backup"), "decoy.txt"),
            consequence = "As above. getNoBackupFilesDir() is a sibling of getFilesDir(), " +
                "so this entry never matched the real wallet directory either.",
        ),
    ).onEach {
        it.file.parentFile?.mkdirs()
        it.file.writeText(DECOY_PREFIX + stamp(it.file.name))
    }

    private fun removePlantedFiles() {
        File(context.noBackupFilesDir, WALLET_DIR).deleteRecursively()
        File(context.filesDir, WALLET_DIR).deleteRecursively()
        File(context.filesDir, "no_backup").deleteRecursively()
        File(context.filesDir, CANARY).delete()
    }

    /** `<index>-<8 hex chars>`, the scheme `LdkStateStore.allocateQuarantineDirectory` uses. */
    private fun quarantineName(): String =
        "%04d-%s".format(1, ByteArray(4).also(random::nextBytes).joinToString("") { "%02x".format(it) })

    /** Distinct per file and per run, so one run's bytes cannot be mistaken for another's. */
    private fun stamp(label: String): String =
        "$label ${ByteArray(8).also(random::nextBytes).joinToString("") { "%02x".format(it) }}"

    /** The result the framework reported for [target] in `bmgr backupnow` output. */
    private fun resultFor(target: String, output: String): String? =
        Regex("""Package\s+${Regex.escape(target)}\s+with result:\s*(.+)""")
            .find(output)
            ?.groupValues
            ?.get(1)
            ?.trim()

    private data class Marker(val what: String, val file: File, val consequence: String)
}
