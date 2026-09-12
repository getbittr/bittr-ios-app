package com.bittr.android

import java.io.File
import org.junit.Assert.assertTrue

/**
 * Read-only view of the Kotlin sources in the `android/` tree, for the guard tests
 * that enforce rules the compiler cannot.
 *
 * Gradle runs unit tests with the working directory set to the module directory
 * (`android/app`), so the Gradle root is one level up. [root] verifies that rather
 * than assuming it: a source-scan test that walks an empty tree passes silently,
 * which is the one failure mode that would make these guards worse than useless.
 */
internal object SourceTree {

    val root: File by lazy {
        val candidate = File("..").canonicalFile
        assertTrue(
            "Expected the Gradle root at $candidate (working dir ${File(".").canonicalFile}), " +
                "but it has no settings.gradle.kts. The guard tests scan the source tree " +
                "from there; if the working directory has moved they would scan nothing " +
                "and pass without checking anything.",
            File(candidate, "settings.gradle.kts").isFile,
        )
        candidate
    }

    /** Every non-generated Kotlin source file under `android/`, excluding [excludeFileNames]. */
    fun kotlinSources(vararg excludeFileNames: String): List<File> {
        val excluded = excludeFileNames.toSet()
        val files = root.walkTopDown()
            .onEnter { it.name != "build" && it.name != ".gradle" }
            .filter { it.isFile && it.extension == "kt" }
            .filterNot { it.name in excluded }
            .toList()
        assertTrue(
            "Found no Kotlin sources under $root — the scan is not looking where it thinks.",
            files.isNotEmpty(),
        )
        return files
    }

    /**
     * Every hand-written `AndroidManifest.xml` under `android/`.
     *
     * Source manifests only — the `build` directories the merger writes into are
     * skipped by [sources], so a guard that scans these is asking "what does this
     * repo declare", not "what ends up in the APK". For the second question, read
     * the merged manifest back through Robolectric's `PackageManager`.
     */
    fun manifests(): List<File> = sources("AndroidManifest.xml") {
        it.name == "AndroidManifest.xml"
    }

    /**
     * Every Gradle build script and version catalog under `android/`.
     *
     * Some rules are cheaper to enforce at the dependency than at the call site:
     * a banned artefact is one line in one file, where the API it exposes could
     * turn up in any of them.
     */
    fun buildFiles(): List<File> = sources("Gradle build files") {
        it.name.endsWith(".gradle.kts") || it.name == "libs.versions.toml"
    }

    /**
     * Files under [root] matching [predicate], skipping build output.
     *
     * Fails when nothing matches. A source-scan guard that walks an empty tree
     * passes silently, which is the one failure mode that would make these guards
     * worse than useless — [what] names what was being looked for when that happens.
     */
    private fun sources(what: String, predicate: (File) -> Boolean): List<File> {
        val files = root.walkTopDown()
            .onEnter { it.name != "build" && it.name != ".gradle" }
            .filter { it.isFile && predicate(it) }
            .toList()
        assertTrue(
            "Found no $what under $root — the scan is not looking where it thinks.",
            files.isNotEmpty(),
        )
        return files
    }

    fun File.repoPath(): String = relativeTo(root).path
}
