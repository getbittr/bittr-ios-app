package com.bittr.android

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * **BIT-8 rule 4, widened by BIT-20 rule 5 — the static half.**
 *
 * Three layers keep wallet material on this device, and this test covers the
 * two that live in the manifest:
 *
 * 1. `android:allowBackup="false"`;
 * 2. `android:dataExtractionRules`, with `<exclude>` entries in **both** the
 *    `<cloud-backup>` and `<device-transfer>` sections;
 * 3. siting every wallet file under `getNoBackupFilesDir()` — that one is
 *    `StateDirLocationTest`, in `:core:wallet-ldk`.
 *
 * **What this test does not do, stated plainly.** It reads configuration. It
 * does not prove that a backup set produced by a real device contains none of
 * this. That is `BackupExclusionTest` (`:app`, `src/androidTest`), which drives
 * `bmgr` on both the cloud-backup and the device-transfer path and now runs on
 * every push in the `wallet-instrumented` job (BIT-59, API 34 `aosp_atd`
 * emulator). Whether the device-transfer half passes is what
 * `wallet-security-properties.md` §4 is waiting on.
 *
 * The distinction matters because
 * whether `allowBackup="false"` alone also suppresses the API 31+ transfer
 * path is exactly the kind of documented-behaviour claim this project has
 * decided not to assert from memory — and it is precisely the question rule 4
 * turns on. Configuration asserted here; behaviour asserted there; neither
 * stands in for the other.
 *
 * Why the transfer path is not belt-and-braces: `match → keep` in the BIT-20
 * guard is only sound if same-seed state cannot arrive from a second device. A
 * discriminator proves state is *yours*, not that it is *current*, and
 * same-seed stale state signs fine — publishing a revoked commitment hands the
 * channel balance to the counterparty. Foreign state cannot sign, so the case
 * the discriminator does not cover is the worse one.
 */
class BackupExclusionRulesTest {

    private companion object {
        val REQUIRED_SECTIONS = listOf("cloud-backup", "device-transfer")

        /** Both the wallet directory and the `no_backup` tree that contains it. */
        val REQUIRED_PATHS = setOf("wallet", "no_backup")
    }

    private val manifest = File(SourceTree.root, "app/src/main/AndroidManifest.xml")
    private val rules = File(SourceTree.root, "app/src/main/res/xml/data_extraction_rules.xml")

    @Test
    fun `backup is off and the extraction rules are wired up`() {
        assertTrue("Expected a manifest at $manifest", manifest.isFile)
        val text = manifest.readText()

        assertTrue(
            "android:allowBackup=\"false\" is layer 1. Flipping it to true puts the " +
                "seed blob and the LDK channel state into a cloud backup.",
            """android:allowBackup="false"""" in text,
        )
        assertTrue(
            "The manifest must point at the extraction rules, or layer 2 is a file " +
                "nobody reads.",
            """android:dataExtractionRules="@xml/data_extraction_rules"""" in text,
        )
    }

    @Test
    fun `both backup paths exclude the wallet directory`() {
        assertTrue("Expected extraction rules at $rules", rules.isFile)
        val document = DocumentBuilderFactory.newInstance()
            .newDocumentBuilder()
            .parse(rules)

        for (section in REQUIRED_SECTIONS) {
            val nodes = document.getElementsByTagName(section)
            assertEquals(
                "data_extraction_rules.xml must declare exactly one <$section>. On API " +
                    "31+ cloud backup and device-to-device transfer are configured " +
                    "separately, and only one of them being covered is the failure this " +
                    "test exists for.",
                1,
                nodes.length,
            )

            val excluded = (nodes.item(0) as Element)
                .getElementsByTagName("exclude")
                .let { list -> (0 until list.length).map { list.item(it) as Element } }
                .filter { it.getAttribute("domain") == "file" }
                .map { it.getAttribute("path") }
                .toSet()

            assertTrue(
                "<$section> must exclude $REQUIRED_PATHS from domain=\"file\"; it " +
                    "excludes $excluded. The LDK state directory is in scope here, not " +
                    "just the seed blob — see the class comment.",
                excluded.containsAll(REQUIRED_PATHS),
            )
        }
    }

    @Test
    fun `no include rule can re-admit the wallet directory`() {
        // An <include> anywhere in this file overrides the default-exclude
        // posture for its domain, which is how a later change re-admits the
        // wallet data without touching a single <exclude> line.
        val document = DocumentBuilderFactory.newInstance()
            .newDocumentBuilder()
            .parse(rules)

        assertEquals(
            "data_extraction_rules.xml must contain no <include> rules. One include " +
                "on domain=\"file\" re-admits everything not explicitly excluded, and " +
                "this test is the only thing that would notice.",
            0,
            document.getElementsByTagName("include").length,
        )
    }
}
