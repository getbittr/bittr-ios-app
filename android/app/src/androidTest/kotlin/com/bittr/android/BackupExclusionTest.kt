package com.bittr.android

import android.content.pm.ApplicationInfo
import android.content.res.XmlResourceParser
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bittr.android.core.wallet.ldk.seed.AndroidKeystoreBlobCodec
import com.bittr.android.core.wallet.ldk.state.WalletPaths
import java.io.File
import java.io.FileInputStream
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.xmlpull.v1.XmlPullParser

/**
 * **BIT-8 rule 4 / BIT-20 rule 5, empirically — the claim §4 of
 * `wallet-security-properties.md` says is the one not yet proven.**
 *
 * `BackupExclusionRulesTest` and `StateDirLocationTest` prove the
 * *configuration* on the JVM: `allowBackup="false"`, both `<cloud-backup>` and
 * `<device-transfer>` excluding the wallet directory, no `<include>`, every
 * wallet path under `getNoBackupFilesDir()`. None of that proves a backup set
 * produced by a real device contains none of it. This does, or says exactly
 * which half it could not.
 *
 * ## Why this test is in `:app` and not in `:core:wallet-ldk`
 *
 * BIT-59 asks for `:core:wallet-ldk:connectedAndroidTest`, and for
 * `KeystoreKeyInfoTest` that is right — the Keystore is a device service and
 * does not care which package calls it. For *this* test it would be worse than
 * useless, and quietly so.
 *
 * An Android library module's instrumented tests run in a self-instrumenting
 * test APK built from the library's own manifest. `:core:wallet-ldk` has no
 * `AndroidManifest.xml` at all, so that APK gets AGP's generated stub: no
 * `android:allowBackup="false"`, no `android:dataExtractionRules`. Backup
 * therefore defaults to **enabled** there. A `bmgr` run against that package
 * would be measuring the opposite configuration from the one we ship, and the
 * most likely result — a backup set that does contain the files — would read as
 * "the exclusion is broken" when it means "the test was pointed at the wrong
 * APK". The inverse is worse: passing for a reason unrelated to our manifest.
 *
 * The property under test is a property of the **installed application**, so
 * the test has to run inside it. `:app`'s androidTest APK instruments
 * `com.bittr.android.regtest` (the debug `applicationIdSuffix`), whose merged
 * manifest is the real one. `:core:wallet-ldk` arrives here as an
 * `androidTestImplementation` dependency — test-only, nothing added to the
 * shipped app, which still binds `:core:wallet-stub`.
 *
 * ## What is asserted, and what is only recorded
 *
 * Hard assertions, in the order a failure would matter:
 *
 * 1. The **installed** package really has backup off (`FLAG_ALLOW_BACKUP`
 *    clear), its merged binary manifest really points `dataExtractionRules` at
 *    our resource, and the rules **as compiled into the APK** exclude the wallet
 *    directory from both sections with no `<include>` re-admitting it. The JVM
 *    tests read the source tree; these read what the platform installed, which
 *    is the artefact a manifest merge or an aapt change could have altered
 *    without the source moving.
 * 2. Wallet material really lands under `no_backup`, written through the real
 *    `WalletPaths` + `AndroidKeystoreBlobCodec`, not a fixture.
 * 3. The backup transport is present and drivable — the vacuity canary. Without
 *    it every assertion below passes by never having run anything.
 * 4. `bmgr backupnow` on this package produces no backup set for it.
 *
 * Recorded, not asserted: the device-to-device transfer path. See
 * [theDeviceTransferPathIsRecordedBecauseItCannotBeDriven]. That gap is the
 * halt condition in `wallet-security-properties.md` §4 and it is reported
 * rather than papered over.
 */
@RunWith(AndroidJUnit4::class)
class BackupExclusionTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    /** The instrumented app under test — `com.bittr.android.regtest` on debug. */
    private val context = instrumentation.targetContext

    private val packageName: String = context.packageName

    private val paths = WalletPaths.forContext(context)

    /**
     * A value we can search a backup set for. Random per run rather than a
     * constant: a constant could match a stale artefact left by an earlier run
     * and turn a real leak into a green.
     */
    private val marker: String = MARKER_PREFIX + System.nanoTime().toString(16)

    @Before
    fun writeWalletBearingState() {
        // Printed so the value survives out of this process. The in-test
        // assertions below can only search `bmgr`'s own stdout, which is a
        // report and not the backup set; check-backup-set.sh greps the
        // transport's on-disk tree for MARKER_PREFIX after the run, which is the
        // backup set itself. See that script's header for why the stronger half
        // has to live outside the test.
        println("BACKUP_EXCLUSION_MARKER=$marker")

        paths.createDirectories()

        // The real wrap, through the real Keystore codec. Writing a hand-rolled
        // byte array here would test the file layout and nothing else.
        paths.seedBlobFile.writeBytes(
            AndroidKeystoreBlobCodec().wrap(
                "$marker void super old faith primary cradle behave crucial".toByteArray(),
            ),
        )
        // Stand-ins for ldk-node's own files. The claim is about the state
        // *directory*, so what matters is that something is in it and that it
        // carries the marker; booting ldk-node to obtain a real sqlite file
        // would add a native dependency and prove nothing extra about backup.
        File(paths.ldkStateDir, "ldk_node_data.sqlite").writeText("$marker channel state")
        paths.discriminatorFile.writeText("$marker discriminator")
        paths.bdkDatabaseFile.writeText("$marker bdk")
    }

    @After
    fun removeWalletBearingState() {
        paths.walletDir.deleteRecursively()
        AndroidKeystoreBlobCodec().deleteKey()
    }

    // --- 1. The installed manifest, not the source XML -------------------------

    @Test
    fun theInstalledPackageHasBackupDisabled() {
        val info = context.packageManager.getApplicationInfo(packageName, 0)

        assertEquals(
            "The installed package $packageName reports FLAG_ALLOW_BACKUP set. " +
                "BackupExclusionRulesTest reads android/app/src/main/AndroidManifest.xml; " +
                "this reads what the platform actually installed, and they have " +
                "disagreed. A manifest merge from a library dependency can re-add " +
                "allowBackup, and nothing on the JVM would notice.",
            0,
            info.flags and ApplicationInfo.FLAG_ALLOW_BACKUP,
        )
    }

    @Test
    fun theInstalledManifestPointsAtOurDataExtractionRules() {
        // API 31+ only: the attribute does not exist below S, where allowBackup
        // and fullBackupContent are the whole story.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return

        // `ApplicationInfo.dataExtractionRulesRes` would say this in one line and
        // is @hide, so it is not available to a test that has to keep compiling.
        // Reading the installed APK's own binary manifest through the app's
        // AssetManager is public API and is strictly better evidence anyway: it
        // is the *merged, compiled, installed* manifest, which is the artefact a
        // library dependency could have changed without the source tree moving.
        val declared = applicationTagAttributes()

        val rules = declared[android.R.attr.dataExtractionRules]
        assertTrue(
            "The installed manifest declares no android:dataExtractionRules. That " +
                "attribute is the ONLY thing configuring the API 31+ " +
                "device-transfer path — allowBackup does not govern it, which is " +
                "the whole reason res/xml/data_extraction_rules.xml exists (see " +
                "its header). Without it the transfer path is unconfigured, " +
                "whatever the source tree says. Attributes found on <application>: " +
                declared.keys.joinToString { "0x%08x".format(it) },
            rules != null,
        )
        assertEquals(
            "The installed manifest's android:dataExtractionRules points at a " +
                "different resource than @xml/data_extraction_rules. Something " +
                "in the merge replaced our rules with another module's.",
            R.xml.data_extraction_rules,
            rules,
        )
    }

    @Test
    fun theInstalledRulesExcludeTheWalletDirectoryFromBothPaths() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return

        // Parsed out of the APK's compiled resources, not off disk.
        // BackupExclusionRulesTest reads the source XML on the JVM; this reads
        // what aapt actually compiled into the installed app, which is the form
        // the platform's backup machinery will consult.
        val excludedBySection = mutableMapOf<String, MutableSet<String>>()
        var section: String? = null

        context.resources.getXml(R.xml.data_extraction_rules).use { parser ->
            var event = parser.eventType
            while (event != XmlPullParser.END_DOCUMENT) {
                if (event == XmlPullParser.START_TAG) {
                    when (parser.name) {
                        "cloud-backup", "device-transfer" -> section = parser.name
                        "exclude" -> section?.let {
                            val domain = parser.getAttributeValue(ANDROID_NS, "domain")
                            val path = parser.getAttributeValue(ANDROID_NS, "path")
                            excludedBySection
                                .getOrPut(it) { mutableSetOf() }
                                .add("$domain:$path")
                        }
                        // An <include> anywhere re-admits what the excludes took
                        // out, and would do it silently. BackupExclusionRulesTest
                        // asserts there is none in the source; this asserts it of
                        // the compiled resource.
                        "include" -> throw AssertionError(
                            "The installed data_extraction_rules.xml contains an " +
                                "<include> in the '$section' section. An include " +
                                "re-admits paths the excludes removed. HALT — see " +
                                "wallet-security-properties.md §4.",
                        )
                    }
                }
                if (event == XmlPullParser.END_TAG &&
                    (parser.name == "cloud-backup" || parser.name == "device-transfer")
                ) {
                    section = null
                }
                event = parser.next()
            }
        }

        listOf("cloud-backup", "device-transfer").forEach { name ->
            val excluded = excludedBySection[name].orEmpty()
            assertTrue(
                "The installed rules have no '$name' section, so that path is " +
                    "unconfigured in the APK the device is running. Found: " +
                    excludedBySection.keys,
                excluded.isNotEmpty(),
            )
            assertTrue(
                "The '$name' section does not exclude the wallet directory in the " +
                    "file domain. Found: $excluded. BIT-20 rule 5 widened this from " +
                    "the seed blob to the whole LDK state directory, because the " +
                    "discriminator proves state is yours and not that it is current.",
                "file:${WalletPaths.WALLET_DIR}" in excluded,
            )
            assertTrue(
                "The '$name' section does not exclude the no_backup tree in the " +
                    "file domain. That is the belt-and-braces entry; losing it " +
                    "means anything new landing under no_backup is no longer " +
                    "covered by name. Found: $excluded",
                "file:no_backup" in excluded,
            )
        }
    }

    // --- 2. Where the material actually landed ---------------------------------

    @Test
    fun everyWalletFileLandedUnderNoBackup() {
        val noBackup = context.noBackupFilesDir.canonicalFile

        val written = listOf(
            paths.seedBlobFile,
            paths.discriminatorFile,
            paths.bdkDatabaseFile,
            File(paths.ldkStateDir, "ldk_node_data.sqlite"),
        )

        written.forEach { file ->
            assertTrue("Expected $file to have been written by the fixture.", file.isFile)
            assertTrue(
                "$file is not under ${noBackup}. Siting is the layer that survives " +
                    "someone flipping allowBackup or adding an <include> rule — see " +
                    "WalletPaths' header. StateDirLocationTest asserts this against an " +
                    "injected directory; this asserts it against the real Context.",
                file.canonicalFile.startsWith(noBackup),
            )
        }

        assertTrue(
            "The wrapped seed blob must not contain the plaintext marker; if it " +
                "does, the blob is not actually encrypted and the rest of this " +
                "test is measuring the wrong risk.",
            !String(paths.seedBlobFile.readBytes(), Charsets.ISO_8859_1).contains(marker),
        )
    }

    // --- 3. The vacuity canary -------------------------------------------------

    /**
     * The counterpart of BIT-62's WebView preflight, and here for the same
     * reason: every `bmgr` assertion in this class is of the form "the backup
     * set does not contain X", and an image with no backup transport satisfies
     * all of them by producing no backup set for any reason at all.
     *
     * So this test does not check our package. It checks that the *mechanism*
     * is alive, by confirming the Backup Manager is enabled and has a transport
     * selected. If this is red, every other `bmgr` result in this class is
     * meaningless and must not be read as evidence.
     */
    @Test
    fun theBackupTransportIsActuallyAvailable() {
        val enabled = shell("bmgr enabled")
        assertTrue(
            "`bmgr enabled` reported: '$enabled'. The Backup Manager is off, so " +
                "`bmgr backupnow` below would decline for a reason that has nothing " +
                "to do with our manifest, and this suite's greens would prove " +
                "nothing. CI enables it in android/scripts/ci-wallet-instrumented.sh; " +
                "locally run `adb shell bmgr enable true`.",
            enabled.contains("currently enabled", ignoreCase = true),
        )

        val transport = shell("bmgr list transports")
        assertTrue(
            "`bmgr list transports` reported: '$transport'. No transport is " +
                "selected (the '*' marks it), so no backup set can be produced at " +
                "all and every exclusion assertion here is vacuous. On an emulator " +
                "select com.android.localtransport/.LocalTransport.",
            transport.contains("*"),
        )
    }

    // --- 4. The backup set itself ----------------------------------------------

    @Test
    fun aCloudBackupRunProducesNoBackupSetForThisPackage() {
        val output = shell("bmgr backupnow $packageName")

        // The platform declines an ineligible package rather than producing an
        // empty set for it. Both readings are a pass for the claim — nothing of
        // ours reached a transport — but they are different sentences, so the
        // assertion accepts either and the message prints what was actually said.
        val declined = listOf(
            "not eligible",
            "not allowed",
            "Package $packageName not installed",
            "no backup",
            "Backup is not allowed",
        ).any { output.contains(it, ignoreCase = true) }

        // NOT a strong signal, and labelled so it cannot be mistaken for one.
        // "Backup finished with result: Success" is what `bmgr` prints at the end
        // of ANY run that completed, including one that backed this package up in
        // full — and the marker could never appear in this output, because bmgr
        // reports on the run and does not echo file contents. So this branch
        // means "bmgr did not visibly refuse", which is weaker than "nothing of
        // ours was backed up" and is accepted only because the platform's exact
        // decline wording varies by API level and image.
        //
        // The strong version of this assertion is not reachable from in here at
        // all: the backup set lives under the transport's own data directory,
        // which is 0700 to another uid, and UiAutomation's shell runs as `shell`
        // rather than root. check-backup-set.sh does it from the host after this
        // suite finishes — `adb root`, then grep the transport tree for
        // MARKER_PREFIX — and that is the check that would catch a real leak
        // through a bmgr run this method called a pass.
        val notVisiblyRefused =
            output.contains("Success", ignoreCase = true) && !output.contains(marker)

        assertTrue(
            "`bmgr backupnow $packageName` did not show the package being excluded " +
                "from the backup set. Raw output:\n$output\n\n" +
                "If this run actually backed the package up, that is the BIT-20 §5.3 " +
                "HALT condition, not a test to loosen: `match -> keep` is then " +
                "shipping on an exclusion the device does not honour, and the guard " +
                "reverts to iOS behaviour (quarantine on anything but a live " +
                "mnemonic) until it is re-decided.",
            declined || notVisiblyRefused,
        )

        assertFalse(
            "The seed marker appeared in bmgr's own output for $packageName, which " +
                "means wallet material reached the backup pipeline. HALT — see " +
                "wallet-security-properties.md §4.",
            output.contains(marker),
        )
    }

    // --- The half that cannot be driven ----------------------------------------

    /**
     * **This is the documented gap, kept visible on purpose.**
     *
     * `bmgr` drives the cloud-backup path only. It has no flag for the API 31+
     * device-to-device transfer path — that runs through
     * `BackupTransport.FLAG_DEVICE_TO_DEVICE_TRANSFER`, which the shell tool
     * does not expose and an instrumented test cannot set, so no test on an
     * emulator can produce a real D2D transfer set and read it back.
     *
     * That matters more than a normal untested path, because
     * `allowBackup="false"` is **not** documented to suppress D2D on API 31+ —
     * which is exactly why `data_extraction_rules.xml` configures
     * `<device-transfer>` separately, and exactly the claim §4 says we will not
     * assert from memory.
     *
     * So this test asserts the strongest thing that is genuinely observable on
     * the device — the rules resource is attached to the *installed* package
     * (also covered above) and the wallet directory is sited where a
     * `<device-transfer>` `<exclude>` names it — and then prints the residual
     * gap so the run itself carries it. It never claims the D2D path is proven.
     */
    @Test
    fun theDeviceTransferPathIsRecordedBecauseItCannotBeDriven() {
        val info = context.packageManager.getApplicationInfo(packageName, 0)
        val rulesAttached = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            applicationTagAttributes()[android.R.attr.dataExtractionRules] != null

        println(
            "BACKUP_EXCLUSION_D2D api=${Build.VERSION.SDK_INT} " +
                "device=${Build.MANUFACTURER}/${Build.MODEL} package=$packageName " +
                "allowBackup=${info.flags and ApplicationInfo.FLAG_ALLOW_BACKUP != 0} " +
                "dataExtractionRulesAttached=$rulesAttached " +
                "walletDir=${paths.walletDir.canonicalPath} " +
                "verdict=NOT_EMPIRICALLY_PROVEN " +
                "reason=bmgr-has-no-device-to-device-mode",
        )

        assertTrue(
            "The device-transfer path is configured only by dataExtractionRules, " +
                "and the installed manifest does not carry it. Nothing excludes " +
                "the wallet directory from a D2D transfer.",
            rulesAttached,
        )
    }

    /**
     * The `<application>` tag of the **installed** APK's merged manifest, as a
     * map from attribute resource id to the resource id it points at (0 when the
     * value is not a resource reference).
     *
     * Reading it through the app's own `AssetManager` is the public-API way to
     * ask what the platform actually installed. `ApplicationInfo` exposes
     * `allowBackup` as a flag but keeps `dataExtractionRulesRes` `@hide`, and a
     * test that reaches for a hidden field is one non-SDK-interface policy change
     * away from failing for a reason unrelated to the wallet.
     */
    private fun applicationTagAttributes(): Map<Int, Int> {
        // The no-argument overload is `openXmlResourceParser(0, fileName)`, and
        // cookie 0 is not guaranteed to be the base APK once split APKs are in
        // play. Trying the low cookies in turn costs nothing and keeps a
        // packaging detail from producing a red that reads as a backup failure.
        // If none of them yield a manifest, that is still a hard failure below —
        // this method never returns a silent empty map.
        val attempts = mutableListOf<String>()
        for (cookie in 0..MAX_ASSET_COOKIE) {
            val found = try {
                context.assets.openXmlResourceParser(cookie, MANIFEST).use { parser ->
                    applicationTagAttributes(parser)
                }
            } catch (throwable: Throwable) {
                attempts += "cookie $cookie: ${throwable.javaClass.simpleName}"
                null
            }
            if (!found.isNullOrEmpty()) return found
            if (found != null) attempts += "cookie $cookie: no <application> tag"
        }
        throw AssertionError(
            "Could not read the installed APK's merged AndroidManifest.xml through " +
                "the app's AssetManager, so this test cannot say what the platform " +
                "installed. This is a packaging/tooling failure, NOT evidence about " +
                "backup exclusion — do not read it as either a pass or the BIT-20 " +
                "halt. Attempts: ${attempts.joinToString("; ")}",
        )
    }

    private fun applicationTagAttributes(parser: XmlResourceParser): Map<Int, Int> {
        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT) {
            if (event == XmlPullParser.START_TAG && parser.name == "application") {
                return (0 until parser.attributeCount).associate { index ->
                    parser.getAttributeNameResource(index) to
                        parser.getAttributeResourceValue(index, 0)
                }
            }
            event = parser.next()
        }
        return emptyMap()
    }

    /**
     * Runs a command as the `shell` user via `UiAutomation`, which is how an
     * instrumented test reaches `bmgr` at all — `bmgr` refuses the app's own
     * uid, and Runtime.exec() from the test process runs as that uid.
     */
    private fun shell(command: String): String =
        instrumentation.uiAutomation.executeShellCommand(command).use { descriptor ->
            FileInputStream(descriptor.fileDescriptor).use { it.readBytes().decodeToString() }
        }

    private companion object {
        /**
         * Shared with `android/scripts/check-backup-set.sh`, which greps the
         * backup transport's on-disk tree for it after this suite runs. Changing
         * it here without changing it there turns that check into one that can
         * never fire — i.e. into a permanent silent pass. `test_check_backup_set.sh`
         * reads both files and fails the `build` job if they drift.
         */
        const val MARKER_PREFIX = "BIT59-SEED-MARKER-"
        const val MANIFEST = "AndroidManifest.xml"
        const val MAX_ASSET_COOKIE = 4
        const val ANDROID_NS = "http://schemas.android.com/apk/res/android"
    }
}
