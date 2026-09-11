package com.bittr.android.core.wallet.ldk

import java.io.File
import org.junit.Assert.assertTrue

/**
 * Read-only view of this module's production sources, for the guards that
 * enforce rules the compiler cannot.
 *
 * Same idiom as `:app`'s `SourceTree`, and the same trap avoided: Gradle runs
 * unit tests with the working directory set to the module directory, so a scan
 * that has drifted would walk nothing and pass silently. That is the one
 * failure mode that makes a guard worse than useless, so [mainSources]
 * verifies it found something and [root] verifies it is looking at the module
 * it thinks it is.
 *
 * Scoped to `src/main` deliberately. The tests themselves have to *name* the
 * banned symbols in order to assert about them, and `StateDirLocationTest`
 * legitimately calls `createDeviceProtectedStorageContext()` to prove the CE
 * and DE directories differ.
 */
internal object WalletSourceTree {

    val root: File by lazy {
        val candidate = File(".").canonicalFile
        assertTrue(
            "Expected the :core:wallet-ldk module directory at $candidate, but it has " +
                "no build.gradle.kts. The guard tests scan src/main from here; if the " +
                "working directory has moved they would scan nothing and pass without " +
                "checking anything.",
            File(candidate, "build.gradle.kts").isFile,
        )
        candidate
    }

    fun mainSources(): List<File> {
        val files = File(root, "src/main").walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .toList()
        assertTrue(
            "Found no Kotlin sources under ${File(root, "src/main")} — the scan is " +
                "not looking where it thinks.",
            files.isNotEmpty(),
        )
        return files
    }

    fun File.modulePath(): String = relativeTo(root).path

    /**
     * [File.readText] with comments removed.
     *
     * The guards have to scan code, not prose. Every banned symbol below is
     * one this module's KDoc *names on purpose* — a rule that cannot be
     * written down next to the thing it constrains is a rule nobody will find
     * when they are about to break it. Stripping comments is what lets the
     * documentation and the guard coexist.
     *
     * Deliberately crude: no string-literal awareness, because a banned symbol
     * inside a string literal in production code is something a reviewer
     * should look at anyway.
     */
    fun codeOf(file: File): String {
        val source = file.readText()
        val out = StringBuilder(source.length)
        var index = 0
        while (index < source.length) {
            when {
                source.startsWith("/*", index) -> {
                    val end = source.indexOf("*/", index + 2)
                    index = if (end < 0) source.length else end + 2
                }
                source.startsWith("//", index) -> {
                    val end = source.indexOf('\n', index)
                    index = if (end < 0) source.length else end
                }
                else -> {
                    out.append(source[index])
                    index++
                }
            }
        }
        return out.toString()
    }
}
