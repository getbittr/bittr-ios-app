package com.bittr.android

import com.bittr.android.SourceTree.code
import com.bittr.android.SourceTree.repoPath
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `:core:wallet-ldk`'s `NoEmbeddedNodeCredentialsTest`, extended to the place
 * BIT-126 moved the credentials to.
 *
 * That test states the rule and the reason: *never mainnet keys, never
 * production node access, never real funds; never commit node credentials.* It
 * enforces it by scanning the library module, which is where a node id would
 * have gone before this issue existed. This issue built the road out — the
 * environment now arrives from `:app` — and the guard has to follow it, or it
 * goes on protecting the one module the values are no longer in.
 *
 * ## Scoped to four files, on purpose
 *
 * The library scan can be module-wide because nothing in `:core:wallet-ldk` has
 * any business holding a URL. `:app` is different: Settings opens three
 * getbittr.com pages, the price screen calls an API, the Academy downloads
 * images. A module-wide endpoint scan here would fire on all of them, and a
 * guard that fires on legitimate code is a guard somebody adds an allowlist to
 * until it means nothing.
 *
 * So it scans exactly the files the node's configuration can reach:
 * `app/build.gradle.kts`, where the `BuildConfig` constants are declared, the
 * two `di/` files that read them, and any committed `gradle.properties`. A
 * credential that arrives by another route is invisible here — which is why
 * [LdkEnvironmentConfigTest] asserts against the *compiled* constants as well.
 * Neither check subsumes the other.
 */
class NoCommittedNodeCredentialsTest {

    private companion object {
        /**
         * A compressed secp256k1 public key as a literal: 66 characters starting
         * `02` or `03`. Lightning node ids, and nothing else these files could
         * legitimately contain, look like that.
         */
        val NODE_ID = Regex("""(?<![0-9a-fA-F])(0[23][0-9a-fA-F]{64})(?![0-9a-fA-F])""")

        /** Any http(s), ssl or tcp endpoint. */
        val ENDPOINT = Regex("""(?:https?|ssl|tcp)://[^"'\s<>]+""")

        /** `host:port`, which is the form an LSP address takes. */
        val HOST_PORT = Regex(""""[A-Za-z0-9.\-]+\.[A-Za-z]{2,}:\d{2,5}"""")
    }

    private fun scanned(): List<File> {
        val files = buildList {
            add(File(SourceTree.root, "app/build.gradle.kts"))
            add(File(SourceTree.root, "app/src/main/kotlin/com/bittr/android/di/WalletModule.kt"))
            add(
                File(
                    SourceTree.root,
                    "app/src/main/kotlin/com/bittr/android/di/LdkEnvironmentConfig.kt",
                ),
            )
            addAll(
                SourceTree.root.walkTopDown()
                    .onEnter { it.name != "build" && it.name != ".gradle" }
                    .filter { it.isFile && it.name == "gradle.properties" },
            )
        }
        // The empty-set failure this repo keeps paying for: a path that has moved
        // makes the scan walk nothing and pass. Named files are checked, not
        // assumed.
        files.take(3).forEach {
            assertTrue(
                "Expected to scan ${it.repoPath()} and it is not there. The node's " +
                    "environment has moved; move this guard with it rather than deleting " +
                    "the line.",
                it.isFile,
            )
        }
        return files
    }

    @Test
    fun `no lightning node id is committed to the app module`() {
        val offenders = scanned().flatMap { file ->
            NODE_ID.findAll(textOf(file))
                .map { "${file.repoPath()}: ${it.groupValues[1].take(12)}…" }
                .toList()
        }

        assertTrue(
            "A Lightning node id is committed. It belongs in a Gradle property or an " +
                "environment variable supplied at build time — app/build.gradle.kts says " +
                "how — not in a file a clone receives. A default here would be reached by " +
                "every build that forgot to override it, which is every build CI makes.\n\n  " +
                offenders.joinToString("\n  "),
            offenders.isEmpty(),
        )
    }

    @Test
    fun `no chain source, gossip or LSP endpoint is committed to the app module`() {
        val offenders = scanned().flatMap { file ->
            (ENDPOINT.findAll(textOf(file)) + HOST_PORT.findAll(textOf(file)))
                .map { "${file.repoPath()}: ${it.value}" }
                .toList()
        }

        assertTrue(
            "A node endpoint is committed. Same reason as the node id: a default that a " +
                "test run or a misconfigured build can reach past is how 'never production " +
                "node access' stops being true without anyone deciding it.\n\n  " +
                offenders.joinToString("\n  "),
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the scan can see a string literal at all`() {
        // Both assertions above pass trivially against an empty read. This proves
        // the files are being read and the literals in them are reaching the
        // regexes, so a green result means "checked" rather than "found nothing".
        assertTrue(
            "Found no quoted string in the scanned files — the scan is not reading what " +
                "it thinks it is.",
            scanned().filter { it.isFile }.any { Regex("""["'][^"']+["']""") in textOf(it) },
        )
    }

    /**
     * Comments stripped for Kotlin, raw for everything else.
     *
     * The Kotlin files name the rule in their KDoc and must go on being able to
     * — that is `SourceTree.code`'s whole reason for existing. `gradle.properties`
     * and `.gradle.kts` are read as-is: the Kotlin stripper does not understand
     * a properties file, and a credential in a Gradle comment is still a
     * credential in the repository.
     */
    private fun textOf(file: File): String = when {
        !file.isFile -> ""
        file.extension == "kt" -> file.code()
        else -> file.readText()
    }
}
