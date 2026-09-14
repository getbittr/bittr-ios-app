package com.bittr.android

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BIT-129: the ABI decision, asserted rather than left as a property of whichever
 * dependencies happen to be on the graph.
 *
 * BIT-126 put `:core:wallet-ldk` on `:app`, which brought `libldk_node.so` and
 * `libbdkffi.so` with it, and `:app:assembleDebug` went to 174 MB — 156 MB of it
 * `lib/`, spread over seven ABI directories. The decision taken in response is
 * written up in android/docs/abi-packaging.md and implemented in the `splits`
 * block of app/build.gradle.kts. This class is what stops it decaying.
 *
 * ### What it is actually guarding against
 *
 * Not a wrong value — a *missing* one. Every part of this decision is about what
 * is NOT in the APK, and configuration that has been deleted fails open: the
 * build still succeeds, the flows still pass, the APK is simply bigger again and
 * offers itself to devices the wallet has no binary for. There is no compiler
 * error and no red flow waiting at the end of that path, which is exactly the
 * shape of thing worth a guard.
 *
 * ### The two halves, and why they are in one class
 *
 * The Gradle half — which ABIs exist and how they are packaged — is read from
 * system properties injected by `app/build.gradle.kts` out of AGP's own resolved
 * DSL objects, not grepped out of the file. So a value set from a build type, a
 * convention plugin, or a second `ndk` block is visible here; a file that still
 * *looks* right is not enough to pass.
 *
 * The CI half — which of the resulting APKs gets installed on the emulator —
 * lives in two files under `.github/` and `android/scripts/`, and neither is
 * reachable from a system property. Those are read as text.
 *
 * They are one class because they are one decision. Splitting them would let the
 * build emit three APKs while CI installs a name that no longer exists, and each
 * half would pass alone.
 */
class AbiPackagingGuardTest {

    /**
     * **The ABIs for which BOTH `libldk_node.so` and `libbdkffi.so` exist.**
     *
     * That is the definition, not a preference, and it is why `x86` is absent
     * while MapLibre still publishes one: ldk-node and BDK do not, so a 32-bit
     * x86 build of this app installs and then dies at the first
     * `System.loadLibrary` the wallet makes.
     *
     * Changing this list means checking that claim against the AARs again. It is
     * duplicated from `supportedAbis` in app/build.gradle.kts on purpose — a
     * guard that read its expectation from the thing it guards would agree with
     * any edit, which is the one property it must not have.
     */
    private val supportedAbis = setOf("arm64-v8a", "armeabi-v7a", "x86_64")

    /**
     * The ABI of the Maestro emulator, and so of the APK CI installs.
     *
     * `arch: x86_64` in .github/workflows/android-maestro.yml, asserted below
     * rather than trusted — see [the emulator's ABI is one bittr supports].
     */
    private val ciAbi = "x86_64"

    /** What `:app:assembleDebug` names the [ciAbi] output. */
    private val ciApk = "app-$ciAbi-debug.apk"

    private val workflow = File(SourceTree.repoRoot, ".github/workflows/android-maestro.yml")
    private val smokeScript = File(SourceTree.repoRoot, "android/scripts/ci-smoke.sh")

    // ---------------------------------------------------------------- Gradle

    /**
     * **bittr supports three ABIs, and the build says so.**
     *
     * Read from AGP's resolved DSL, through whichever of the two mechanisms is
     * carrying the list — see [the ABI set is declared by exactly one mechanism]
     * for why there are two and why only one may be in use.
     *
     * The failure that matters here is the empty one. Delete the `splits` block
     * and this reads `[]`, the APK goes back to seven `lib/` directories, and
     * nothing else in the repository notices.
     */
    @Test
    fun `the app is packaged for exactly the ABIs the wallet has binaries for`() {
        assertEquals(
            "The ABIs this build packages are not the ones bittr supports. This set is " +
                "the ABIs for which ldk-node AND BDK both publish a binary; adding one " +
                "without checking that ships an APK that installs and then fails at " +
                "System.loadLibrary. See the `splits` block in app/build.gradle.kts and " +
                "android/docs/abi-packaging.md.",
            supportedAbis,
            declaredAbis(),
        )
    }

    /**
     * **One mechanism declares the list, and AGP agrees that is all there may be.**
     *
     * `defaultConfig.ndk.abiFilters` and `splits.abi` both narrow the packaged
     * ABIs, and AGP 9.4.0 refuses to configure when both are set — with the same
     * three values in each, `:app:assembleDebug` fails with "Conflicting
     * configuration : 'armeabi-v7a,arm64-v8a,x86_64' in ndk abiFilters cannot be
     * present when splits abi filters are set". So the build cannot reach this
     * test with both populated, and this assertion is really about the other
     * direction: *neither*, which configures fine and packages everything.
     *
     * The repo uses `splits` today because an APK is what it produces, and
     * `ndk.abiFilters` alone would still emit one universal APK. When a release
     * App Bundle lands, that swaps: `splits.abi` does not apply to `bundle*`
     * tasks. [the app is packaged for exactly the ABIs the wallet has binaries
     * for] is written against the union of the two precisely so that migration
     * does not have to touch it.
     */
    @Test
    fun `the ABI set is declared by exactly one mechanism`() {
        val ndk = abiProperty("bittr.abi.filters")
        val splits = abiProperty("bittr.abi.splits")

        assertTrue(
            "Neither defaultConfig.ndk.abiFilters nor splits.abi declares an ABI list, so " +
                "this build packages every ABI its dependencies happen to carry — seven " +
                "lib/ directories and a 174 MB debug APK, which is what BIT-129 decided " +
                "against. See android/docs/abi-packaging.md.",
            ndk.isNotEmpty() || splits.isNotEmpty(),
        )
        assertTrue(
            "Both defaultConfig.ndk.abiFilters ($ndk) and splits.abi ($splits) are set. " +
                "AGP 9.4.0 fails configuration when both are present, even with identical " +
                "values, so this build should not exist — if it does, the properties in " +
                "app/build.gradle.kts have drifted from the DSL they claim to read.",
            ndk.isEmpty() || splits.isEmpty(),
        )
    }

    /**
     * **No universal APK.**
     *
     * `isUniversalApk = true` would restore the 174 MB artefact alongside the
     * three per-ABI ones, and — because the upload path and the install below are
     * both named — restore it *silently*: CI would keep installing the x86_64
     * split and the only symptom would be a build that got slower.
     *
     * Vacuously true when `splits` is not the mechanism in use, which is the
     * App Bundle case; asserted anyway, because AGP reports `false` there and a
     * `true` would mean something has been configured that nothing reads.
     */
    @Test
    fun `no universal APK is emitted`() {
        assertEquals(
            "splits.abi.isUniversalApk is on. That adds back the every-ABI APK this " +
                "decision removed, and nothing downstream would report it: ci-smoke.sh " +
                "installs $ciApk by name either way.",
            "false",
            System.getProperty("bittr.abi.universalApk"),
        )
    }

    // -------------------------------------------------------------------- CI

    /**
     * **The emulator's ABI is one bittr supports.**
     *
     * The whole CI half rests on `arch: x86_64`. An emulator job on an ABI the
     * app is not packaged for would install nothing usable — or, worse, install
     * an APK whose `lib/` the image cannot load, and fail inside a flow rather
     * than at install.
     *
     * Every `arch:` in this workflow, not only the Maestro job's: the instrumented
     * jobs build and install their own APKs through `connectedDebugAndroidTest`,
     * and AGP picks a split for them by device ABI. An arch added there has the
     * same requirement even though no line in this repo names its APK.
     */
    @Test
    fun `the emulator's ABI is one bittr supports`() {
        val arches = ARCH.findAll(workflow.readText()).map { it.groupValues[1] }.toSet()
        assertTrue(
            "No `arch:` found in ${workflow.name} — this guard is not reading what it " +
                "thinks it is.",
            arches.isNotEmpty(),
        )
        assertTrue(
            "${workflow.name} boots emulators on $arches, and ${arches - supportedAbis} is " +
                "not an ABI this app is packaged for (see the `splits` block in " +
                "app/build.gradle.kts). Adding an emulator arch means deciding which APK " +
                "gets installed on it, which is why this is red rather than absent.",
            supportedAbis.containsAll(arches),
        )
        assertTrue(
            "The Maestro emulator arch used to be $ciAbi and this workflow no longer " +
                "mentions it. ci-smoke.sh installs $ciApk by name; update both together.",
            ciAbi in arches,
        )
    }

    /**
     * **CI installs the one APK the build job uploads.**
     *
     * Two files, one value. The build job's `Upload APK` step names a single
     * output; `ci-smoke.sh` installs a single file out of the artifact it was
     * downloaded into. If those ever disagree the failure lands after an AVD
     * boot, in the emulator job — twenty minutes into a run, as a missing file.
     */
    @Test
    fun `the uploaded APK and the installed APK are the same file`() {
        val uploaded = UPLOAD_PATH.findAll(workflow.readText())
            .map { it.groupValues[1] }
            .toSet()
        assertEquals(
            "The `Upload APK` step in ${workflow.name} publishes $uploaded. It must " +
                "publish exactly the APK ci-smoke.sh installs — a widened glob puts the " +
                "other two splits (127 MB) through upload and download on every run for " +
                "an emulator that cannot use them.",
            setOf(ciApk),
            uploaded,
        )

        val code = shellCode(smokeScript)
        val installed = APK_NAME.findAll(code).map { it.groupValues[1] }.toSet()
        assertEquals(
            "ci-smoke.sh installs $installed. Expected exactly $ciApk, the APK the build " +
                "job uploads and the one matching the emulator's ABI.",
            setOf(ciApk),
            installed,
        )
    }

    /**
     * **The install is by name, not by glob.**
     *
     * Installing a `*.apk` glob out of the `apk` directory was correct while
     * there was one APK and is a trap now. (The glob cannot be written here: in
     * Kotlin a block comment nests, so the slash-star it contains would open a
     * comment inside this one.)
     *
     * With the three splits present it expands to three arguments and
     * `adb install` reads the extras as flags; with none present, `bash` passes
     * the unexpanded literal and adb tries to install a file called `*.apk`. Both
     * are twenty-minute failures, and neither says "ABI" anywhere in its message.
     *
     * Comment lines are stripped first — see [shellCode]. The comment above that
     * install quotes the old glob, and a guard that treats the explanation of a
     * ban as a violation gets the explanation deleted.
     */
    @Test
    fun `the emulator install names an APK rather than globbing`() {
        val globbed = shellCode(smokeScript)
            .lineSequence()
            .filter { it.contains("adb install") && it.contains("*") }
            .toList()
        assertTrue(
            "ci-smoke.sh globs its install: $globbed. `:app:assembleDebug` emits one APK " +
                "per ABI and no universal one, so a glob resolves to three files (adb " +
                "reads the extras as flags) or, if the artifact is empty, to the literal " +
                "string. Install $ciApk by name.",
            globbed.isEmpty(),
        )
    }

    // --------------------------------------------------------------- helpers

    /** The ABIs this build packages, via whichever mechanism declares them. */
    private fun declaredAbis(): Set<String> =
        abiProperty("bittr.abi.filters") + abiProperty("bittr.abi.splits")

    /**
     * A comma-separated ABI list injected by `app/build.gradle.kts`.
     *
     * A missing property is a failure and not a skip: it means these tests ran
     * outside the Gradle build that supplies them, and the assertions above would
     * otherwise all compare empty sets and report on nothing.
     */
    private fun abiProperty(name: String): Set<String> {
        val raw: String? = System.getProperty(name)
        assertNotNull(
            "System property `$name` is unset. It is injected by the " +
                "testOptions.unitTests block in app/build.gradle.kts, so this test has to " +
                "run under Gradle: ./gradlew :app:test",
            raw,
        )
        return raw.orEmpty().split(',').map { it.trim() }.filter { it.isNotEmpty() }.toSet()
    }

    /**
     * [file]'s contents with whole-line `#` comments removed.
     *
     * The same reason `SourceTree.code()` exists for Kotlin: these scripts explain
     * the rules they follow, and prose that names a banned form is how the ban
     * stays understood.
     *
     * Whole-line comments only. A trailing `# ...` on a code line is still
     * scanned, which is a known edge rather than a handled one — stripping those
     * correctly means knowing whether the `#` is inside a quoted string, and no
     * line in this script needs it.
     */
    private fun shellCode(file: File): String {
        assertTrue("${file.path} does not exist.", file.isFile)
        return file.readLines()
            .filterNot { it.trimStart().startsWith("#") }
            .joinToString("\n")
    }

    private companion object {
        /** `arch: x86_64` under an android-emulator-runner step. */
        val ARCH = Regex("""^\s*arch:\s*(\S+)\s*$""", RegexOption.MULTILINE)

        /** The file name at the end of an `outputs/apk/debug/...` upload path. */
        val UPLOAD_PATH = Regex("""outputs/apk/debug/(\S+)""")

        /** Any `app-*.apk` the smoke script refers to. */
        val APK_NAME = Regex("""\b(app-[A-Za-z0-9_.-]+\.apk)\b""")
    }
}
