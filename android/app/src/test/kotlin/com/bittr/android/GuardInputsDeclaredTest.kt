package com.bittr.android

import com.bittr.android.SourceTree.repoPath
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * **Keeps the guard tests' real inputs declared to the tasks that run them.**
 *
 * Most tests touch only what the compiler put on their classpath, and Gradle
 * knows that classpath. The guards do not. They open files by path at runtime —
 * another source set's sources, another module's sources, a shell script, a
 * shared JSON file outside the Gradle root — and nothing infers that. Unless the
 * test task is told, it sees identical inputs across a commit that changed a
 * guarded file, is called up-to-date or restored from the build cache, and the
 * assertion never executes.
 *
 * That does not make the guard slow, it makes it silent. A guard that did not
 * run and a guard that passed are the same exit code and the same green check
 * mark — the single failure mode this whole family of tests exists to refuse —
 * and it lands hardest on exactly the commit that most needed the guard, because
 * that is the commit whose change Gradle cannot see.
 *
 * Measured on BIT-113, on the tree this file is in: `:app:testDebugUnitTest`
 * reported `UP-TO-DATE / BUILD SUCCESSFUL` over an edit to `BackupExclusionTest`
 * that `BackupExclusionInstrumentationGuardTest` fails on under `--rerun`, and a
 * fresh checkout at the same path took that stale green result `FROM-CACHE`.
 *
 * So each affected module declares the tree its tests read, under one agreed
 * property name, and this is what stops the next one forgetting. It checks the
 * coupling textually, like every other guard here: it can tell you a declaration
 * is missing, not that an existing one is wide enough. Width is proved the way
 * the bug was found — break a guarded file, run without `--rerun`, require red.
 */
class GuardInputsDeclaredTest {

    private companion object {

        /**
         * The `withPropertyName` every such declaration carries, so that one
         * grep answers "does this module tell Gradle what its tests read".
         */
        const val PROPERTY = "sourcesReadAtRuntime"

        /**
         * A `java.io.File` built from a path literal — a test reaching for
         * something the compiler never saw.
         *
         * `File(SourceTree.root, …)` is deliberately not matched: the module
         * owning the root is already found through the file that defines it, and
         * matching every call site would name the same module again. The
         * converse — a test that builds its path some other way, through
         * `Paths.get` or a helper in another module — is not found at all. That
         * is written down as a known edge rather than implied to be handled; the
         * check is worth having for the shape that has occurred three times.
         */
        val RUNTIME_FILE_READ = Regex("\\bFile\\(\\s*\"")

        /**
         * The modules doing this today, asserted as a lower bound rather than as
         * an exact set — a new one should be caught by the check below, not by
         * this list.
         *
         * It is here because the scan is the part that can fail quietly: a
         * regex that has drifted into matching nothing reports every module as
         * compliant and passes. Same reason [SourceTree] refuses to return an
         * empty file list.
         */
        val KNOWN_SCANNERS = setOf("app", "core/wallet-ldk", "feature/map")
    }

    @Test
    fun `every module whose tests open files by path declares them as task inputs`() {
        val scanners = SourceTree.kotlinSources()
            .filter { "/src/test/" in it.slashPath() }
            .filter { RUNTIME_FILE_READ.containsMatchIn(SourceTree.codeOf(it)) }

        val modules = scanners.mapNotNull(::moduleOf).distinct().sortedBy { it.slashPath() }
        val found = modules.map { it.slashPath() }

        assertTrue(
            "No test source opens a file by path, which cannot be true while SourceTree " +
                "itself is one of them. RUNTIME_FILE_READ has drifted — and a scan that " +
                "matches nothing reports every module as compliant and passes.",
            modules.isNotEmpty(),
        )
        assertTrue(
            "Expected $KNOWN_SCANNERS among the modules whose tests read files at runtime, " +
                "found $found. If one genuinely stopped doing it, drop it from " +
                "KNOWN_SCANNERS in the same commit. If the scan stopped seeing it, fix the " +
                "scan: everything below this line is then checking nothing.",
            found.containsAll(KNOWN_SCANNERS),
        )

        val undeclared = modules.filterNot {
            """withPropertyName("$PROPERTY")""" in File(it, "build.gradle.kts").readText()
        }
        assertTrue(
            "${undeclared.map { it.slashPath() }} run tests that open files by path, and " +
                "their build files do not declare those files as task inputs. Gradle will " +
                "call the test task up-to-date — or hand it back from the build cache CI " +
                "restores — across a commit that changes one of them, and the assertions " +
                "will not run: green, in seconds, having checked nothing. Add to the " +
                "module's build.gradle.kts:\n" +
                "    tasks.withType<Test>().configureEach {\n" +
                "        inputs.files(<the tree those tests read>)\n" +
                "            .withPathSensitivity(PathSensitivity.RELATIVE)\n" +
                "            .withPropertyName(\"$PROPERTY\")\n" +
                "    }\n" +
                "See app/build.gradle.kts for the shape and BIT-113 for what it cost to " +
                "find. Then negative-control it: break the guarded file, run the task " +
                "WITHOUT --rerun, and require red.",
            undeclared.isEmpty(),
        )
    }

    /** [repoPath] with `/` separators, so the literals above read the same everywhere. */
    private fun File.slashPath(): String = repoPath().replace(File.separatorChar, '/')

    /** The nearest directory at or above [file] that Gradle treats as a module. */
    private fun moduleOf(file: File): File? {
        var dir: File? = file.parentFile
        while (dir != null && dir != SourceTree.root) {
            if (File(dir, "build.gradle.kts").isFile) return dir
            dir = dir.parentFile
        }
        return null
    }
}
