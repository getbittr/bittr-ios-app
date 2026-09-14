package com.bittr.android.core.wallet.ldk.state

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * **After `createDirectories()`, every path this class defines is writable.**
 *
 * That is the contract callers actually rely on, and it is the one that broke.
 * Splitting `bdk_store` out of the wallet directory moved
 * [WalletPaths.bdkDatabaseFile] one level deeper without adding the new
 * directory to [WalletPaths.createDirectories], so
 * `paths.bdkDatabaseFile.writeText(…)` began throwing:
 *
 * ```
 * java.io.FileNotFoundException:
 *   /data/user/0/com.bittr.android.regtest/no_backup/wallet/bdk_store/bdk_wallet.sqlite:
 *   open failed: ENOENT (No such file or directory)
 * ```
 *
 * Nothing on the JVM caught it. Every unit-test caller happened to write only
 * to paths whose parents `createDirectories()` still made, so the whole suite
 * stayed green and the failure surfaced on an emulator, in
 * `InstalledBackupConfigurationTest`'s `@Before`, three tests at a time and
 * seven minutes into a CI run. The production path is not affected —
 * `BdkStore.prepare` makes its own directory — which is exactly why this went
 * unnoticed: the contract was broken for everyone *except* the one caller that
 * did not depend on it.
 *
 * ### Why it reflects over the properties instead of listing them
 *
 * A hand-written list is the same failure one move later. The next path added
 * to [WalletPaths] would be absent from the list, the list would still pass,
 * and the reason to trust it would be gone. Enumerating `File`-valued getters
 * means a new path is covered the moment it is declared — the test cannot be
 * left behind by a change it exists to catch.
 *
 * ### Why *parents*, and why that needs no exception for the quarantine
 *
 * The invariant is "a caller may write here without creating anything first",
 * which is a claim about each path's **parent**. Stating it that way makes
 * [WalletPaths.quarantineRoot] fall out correctly rather than needing to be
 * excluded: `LdkStateStore` allocates the root at the moment it quarantines, so
 * the root itself must *not* exist up front — but its parent must, or the
 * allocation fails. An "every directory exists" test would have had to carve
 * the quarantine out by name, and a carve-out by name is where the next
 * omission hides.
 */
class WalletPathsCreateDirectoriesTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `every path is writable once the directories have been created`() {
        val paths = WalletPaths(temporaryFolder.newFolder("no_backup"))
        paths.createDirectories()

        for ((name, path) in pathsOf(paths)) {
            val parent = path.parentFile
            assertTrue(
                "WalletPaths.$name resolves to $path, whose parent directory $parent does " +
                    "not exist after createDirectories(). A caller writing there gets " +
                    "ENOENT — which is how the bdk_store split reached an emulator. Add " +
                    "the missing directory to createDirectories(); do not make the caller " +
                    "mkdirs() around it, because the next caller will not.",
                parent != null && parent.isDirectory,
            )

            // The parent existing is the claim; this is the claim being used.
            // A directory property fails here rather than in some later caller
            // if it was created as a file, which mkdirs() on a clashing path
            // would otherwise leave to surface much further away.
            val probe = File(path.parentFile, "${path.name}.writable-probe")
            probe.writeText("probe")
            assertTrue("Could not write beside WalletPaths.$name at $probe.", probe.isFile)
            probe.delete()
        }
    }

    /**
     * Every `File`-valued property of [WalletPaths], by reflection over its
     * getters — Java reflection rather than `kotlin-reflect`, which this module
     * does not depend on and which is not worth adding for one test.
     */
    private fun pathsOf(paths: WalletPaths): List<Pair<String, File>> {
        val found = WalletPaths::class.java.methods
            .filter {
                it.parameterCount == 0 &&
                    it.returnType == File::class.java &&
                    it.name.startsWith("get")
            }
            .sortedBy { it.name }
            .map { it.name.removePrefix("get").replaceFirstChar(Char::lowercase) to it.invoke(paths) as File }

        assertTrue(
            "Found no File-valued properties on WalletPaths. The reflection has drifted, " +
                "and a scan that matches nothing passes without checking anything.",
            found.isNotEmpty(),
        )
        return found
    }
}
