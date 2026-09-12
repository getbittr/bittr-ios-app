package com.bittr.android

import android.content.pm.ApplicationInfo
import android.content.res.XmlResourceParser
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.bittr.android.core.wallet.ldk.seed.AndroidKeystoreBlobCodec
import com.bittr.android.core.wallet.ldk.state.WalletPaths
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.xmlpull.v1.XmlPullParser

/**
 * **What the platform actually installed — the configuration half of BIT-8
 * rule 4 / BIT-20 rule 5, asserted on the device rather than on the JVM.**
 *
 * [BackupExclusionTest] is the behavioural half: it plants a wallet-bearing
 * install, drives `bmgr` on both the cloud-backup and the device-transfer path,
 * restores, and asserts nothing of ours came back. That is the test BIT-20
 * rule 5 turns on and it is the one to read first.
 *
 * This class answers a different question, and it is the question a *red*
 * `BackupExclusionTest` needs answered before it can be called a halt: **is the
 * configuration this device is running the configuration we wrote?**
 *
 * `BackupExclusionRulesTest` and `StateDirLocationTest` read the source tree on
 * the JVM — `android/app/src/main/AndroidManifest.xml` and
 * `res/xml/data_extraction_rules.xml` as committed. Between that source and a
 * running install there is a manifest merge and an `aapt` compile, and both can
 * change the answer without the source moving: a library dependency re-adding
 * `allowBackup`, a merge pointing `dataExtractionRules` at another module's
 * resource, an `<include>` arriving in the compiled XML. Nothing on the JVM
 * would notice any of those. These four tests read the **merged, compiled,
 * installed** artefacts through public API and would.
 *
 * ## Why it is in `:app`
 *
 * The same reason [BackupExclusionTest] is, and it applies harder here, because
 * every assertion below is literally about the installed package's manifest. An
 * Android library module's instrumented tests are self-instrumenting: the
 * package under test would be `…core.wallet.ldk.test`, whose AGP-generated stub
 * manifest carries neither `allowBackup="false"` nor `dataExtractionRules`.
 * Asserting our backup configuration against that package would assert it
 * against a manifest we do not ship. `:app`'s androidTest APK instruments
 * `com.bittr.android.regtest`, whose merged manifest is the real one.
 *
 * ## Reading a failure
 *
 * A red here and a red in [BackupExclusionTest] mean different things, which is
 * why they are separate classes rather than separate methods:
 *
 * - Red **here**, green there: the install is misconfigured but the platform
 *   excluded the material anyway. Fix the configuration; do not conclude
 *   anything about rule 5 from the green.
 * - Green here, red **there**: the configuration is exactly what we wrote and
 *   the device honoured none of it. That is the BIT-20 §5.3 halt on
 *   `match → keep`, with the "we misconfigured it" explanation already ruled
 *   out — which is the whole reason this class runs alongside.
 */
@RunWith(AndroidJUnit4::class)
class InstalledBackupConfigurationTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    /** The instrumented app under test — `com.bittr.android.regtest` on debug. */
    private val context = instrumentation.targetContext

    private val packageName: String = context.packageName

    private val paths = WalletPaths.forContext(context)

    /**
     * A value distinctive enough to search for. Random per run rather than a
     * constant: a constant could match a stale artefact left by an earlier run.
     * Nothing outside this class greps for it — the backup set itself is
     * [BackupExclusionTest]'s marker and `check-backup-set.sh`'s — it is here
     * so [everyWalletFileLandedUnderNoBackup] can tell a wrapped blob from a
     * plaintext one.
     */
    private val marker: String = "INSTALLED-BACKUP-CONFIG-" + System.nanoTime().toString(16)

    @Before
    fun writeWalletBearingState() {
        paths.createDirectories()

        // The real wrap, through the real Keystore codec. Writing a hand-rolled
        // byte array here would test the file layout and nothing else.
        paths.seedBlobFile.writeBytes(
            AndroidKeystoreBlobCodec().wrap(
                "$marker void super old faith primary cradle behave crucial".toByteArray(),
            ),
        )
        // Stand-ins for ldk-node's own files. The claim is about the state
        // *directory*, so what matters is that something is in it; booting
        // ldk-node to obtain a real sqlite file would add a native dependency
        // and prove nothing extra about where the file landed.
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
                            excludedBySection
                                .getOrPut(it) { mutableSetOf() }
                                .add("${attr(parser, "domain")}:${attr(parser, "path")}")
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
     * An `<exclude>` attribute, read from the namespace it is actually in.
     *
     * **This is what made the test red while the app was correct.** Unlike the
     * manifest, `data-extraction-rules` declares no `xmlns:android` and its
     * `domain`/`path` attributes are UNPREFIXED — they live in the null
     * namespace. Reading them with the android namespace returned `null` for
     * every one, so each entry was recorded as the string `"null:null"` and the
     * "does not exclude the wallet directory" assertion failed against a config
     * that excludes it correctly.
     *
     * The failure mode to keep in mind is the opposite one: a silent `null` here
     * builds a set that matches nothing, and had the assertions been written the
     * other way round (asserting some path is ABSENT) this same bug would have
     * produced a permanent green. So a missing attribute throws rather than
     * returning null — `<exclude>` without a domain and path is malformed, and
     * this test may not quietly agree with it.
     */
    private fun attr(parser: XmlResourceParser, name: String): String =
        parser.getAttributeValue(null, name)
            ?: parser.getAttributeValue(ANDROID_NS, name)
            ?: throw AssertionError(
                "An <exclude> in the installed data_extraction_rules.xml has no " +
                    "'$name' attribute in either the null or the android namespace. " +
                    "That is a malformed rule, and treating it as an empty match " +
                    "would let this test pass over a rule the platform cannot apply.",
            )

    private companion object {
        const val MANIFEST = "AndroidManifest.xml"
        const val MAX_ASSET_COOKIE = 4
        const val ANDROID_NS = "http://schemas.android.com/apk/res/android"
    }
}
