plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
    // BIT-133. Reads `src/<buildType>/google-services.json` and generates the
    // string resources FirebaseApp initialises from at process start. Applied
    // last, which is the order Google documents and the order that matters: the
    // plugin hooks the variants the Android plugin has already created.
    //
    // It is also a build-time check GoogleServicesConfigTest could only
    // approximate — "No matching client found for package name" fails the build
    // if the config and the applicationId ever drift. That test stays, because
    // it asserts the *two-project split* as well, which the plugin knows nothing
    // about.
    alias(libs.plugins.google.services)
}

/**
 * The node's deployment configuration, from outside the repository.
 *
 * Each entry is a `BuildConfig` constant name paired with the Gradle property
 * and environment variable it may be supplied by, in that order of precedence.
 * Absent means empty string — see the `ldkEnvironment.forEach` call below for
 * why an unconfigured build is normal and not an error.
 *
 * `providers.gradleProperty` / `environmentVariable` rather than
 * `project.findProperty` and `System.getenv`: both are configuration-cache-safe
 * inputs, so changing one re-runs configuration instead of silently baking
 * yesterday's value into today's APK.
 */
val ldkEnvironment: Map<String, String> = listOf(
    Triple("LDK_CHAIN_SOURCE_URL", "bittr.ldk.chainSourceUrl", "BITTR_LDK_CHAIN_SOURCE_URL"),
    // The on-chain wallet's Electrum server, which is a different value from the
    // node's chain source on every network but mainnet — see LdkEnvironment.
    Triple("LDK_ELECTRUM_URL", "bittr.ldk.electrumUrl", "BITTR_LDK_ELECTRUM_URL"),
    Triple(
        "LDK_RAPID_GOSSIP_SYNC_URL",
        "bittr.ldk.rapidGossipSyncUrl",
        "BITTR_LDK_RAPID_GOSSIP_SYNC_URL",
    ),
    Triple("LDK_LIGHTNING_NODE_ID", "bittr.ldk.lightningNodeId", "BITTR_LDK_LIGHTNING_NODE_ID"),
    Triple(
        "LDK_LIGHTNING_NODE_ADDRESS",
        "bittr.ldk.lightningNodeAddress",
        "BITTR_LDK_LIGHTNING_NODE_ADDRESS",
    ),
    Triple("LDK_LSPS2_TOKEN", "bittr.ldk.lsps2Token", "BITTR_LDK_LSPS2_TOKEN"),
).associate { (field, property, variable) ->
    val raw = providers.gradleProperty(property)
        .orElse(providers.environmentVariable(variable))
        .getOrElse("")
        .trim()
    // A value carrying a quote or a backslash would break out of the generated
    // Java string literal and fail to compile — or, worse, compile into
    // something else. Refused rather than escaped: none of these five values has
    // any business containing either character, so one that does is a
    // mis-supplied property and should say so at configuration time.
    require(raw.none { it == '"' || it == '\\' }) {
        "$property must not contain a quote or a backslash (supplied via $property or $variable)"
    }
    field to raw
}

android {
    namespace = "com.bittr.android"
    compileSdk = libs.versions.compileSdk.get().toInt()

    /**
     * The ABIs bittr supports, named once and applied to every variant (BIT-129).
     *
     * BIT-126 put `:core:wallet-ldk` on this module's graph, which brought
     * `libldk_node.so` and `libbdkffi.so` with it. The universal debug APK went to
     * **174 MB**, of which **156 MB is `lib/`** — measured on `d882d1e8`, and
     * written down in android/docs/abi-packaging.md with the per-ABI split.
     *
     * WHY THIS LIST AND NOT THE ONE THE DEPENDENCIES HAPPEN TO CARRY
     *
     * Without this filter the APK ships seven `lib/` directories, and four of them
     * are not a supported configuration of this app:
     *
     *   - `armeabi`, `mips`, `mips64` — JNA's `libjnidispatch.so`, for three ABIs
     *     the NDK removed in r17 (2017). No Android device in support has ever run
     *     them. ~0.4 MB, and cheap to carry, but they are noise in every size
     *     measurement anyone takes of this APK from here on.
     *   - `x86` (32-bit) — this one is not noise. **ldk-node and BDK publish no
     *     32-bit x86 binary.** MapLibre does, so today a 32-bit x86 device installs
     *     bittr successfully and then dies on the first `System.loadLibrary` the
     *     wallet makes. Listing the ABIs the wallet actually has turns "installs,
     *     then crashes" into "not offered", which is the honest state: an app whose
     *     whole purpose is the node cannot support an ABI the node has no build for.
     *
     * So this is a correctness statement first and a size one second. The three
     * entries are exactly the ABIs for which BOTH `libldk_node.so` and
     * `libbdkffi.so` exist. Adding a fourth without checking that is how the
     * crash-on-load case comes back.
     *
     * DEBUG AND RELEASE GET THE SAME LIST, DELIBERATELY
     *
     * The cheap way to shrink what CI installs is `ndk.abiFilters` on the debug
     * build only. This repo does not do that — see the `androidComponents` block
     * at the bottom of this file, which exists because a release-only gap in what
     * gets tested had already cost us a silently dead assertion once. `splits`
     * below is what makes the CI saving available without buying a second
     * divergence: it changes how a variant is *packaged*, not what it contains.
     *
     * WHY THE LIST IS APPLIED THROUGH `splits` AND NOT `defaultConfig.ndk`
     *
     * Because AGP will not take both, and that is a hard error rather than a
     * preference. Setting the two to the *same* three ABIs fails configuration
     * with "Conflicting configuration : 'armeabi-v7a,arm64-v8a,x86_64' in ndk
     * abiFilters cannot be present when splits abi filters are set" — verified
     * against AGP 9.4.0, which is the version in gradle/libs.versions.toml.
     *
     * So one of them carries the list, and for an APK it has to be `splits`:
     * `ndk.abiFilters` alone would shrink every APK to the same three ABIs but
     * still emit ONE universal APK, leaving CI pushing all three. The reverse
     * trade arrives with the App Bundle — `splits.abi` does not apply to
     * `bundle*` tasks, so a bundle built today would contain all seven `lib/`
     * directories. That is not a live problem (this repo has no signing config
     * and produces no bundle; see the `release` build type below) and it is the
     * one thing that must change when it becomes one: swap this block for
     * `defaultConfig.ndk.abiFilters`, and let Play do the splitting.
     * AbiPackagingGuardTest is written to accept either mechanism for exactly
     * that reason — it asserts the ABI SET, not the block that spells it.
     */
    val supportedAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")

    /*
     * One APK per ABI, for every variant, with no universal APK (BIT-129).
     *
     * WHY THIS IS NOT THE DIVERGENCE IT LOOKS LIKE
     *
     * The objection to shrinking the CI APK is that Maestro would stop testing the
     * build users get. It does not apply here, and the reason is a property of the
     * platform rather than a judgement call: **`PackageManager` picks ONE primary
     * ABI at install time and loads only that directory.** The Maestro emulator is
     * `x86_64` (see android-maestro.yml), so on every run to date the arm64-v8a,
     * armeabi-v7a and x86 libraries inside the universal APK were pushed over adb,
     * written to disk, and never opened. A universal APK ships more; it does not
     * test more. Splitting changes what travels, and changes nothing about what
     * executes.
     *
     * What DOES differ between the emulator and a user's phone is the ABI itself —
     * CI has exercised x86_64 Rust and users run arm64 — and that was already true
     * before this block and is unchanged by it. It is the reason the nightly
     * regtest suite exists; it is not something a universal APK was fixing.
     *
     * `isUniversalApk = false`: there is no consumer for a 174 MB artefact that no
     * device would use more than a third of. `:app:assembleDebug` now writes
     * app-arm64-v8a-debug.apk, app-armeabi-v7a-debug.apk and app-x86_64-debug.apk
     * instead of app-debug.apk — android/scripts/ci-smoke.sh installs the third by
     * name, and AbiPackagingGuardTest holds it to that.
     *
     * NOT `packaging.jniLibs.useLegacyPackaging = true`, which is the other obvious
     * lever and is a trap. Every `.so` above is stored uncompressed because AGP
     * defaults `extractNativeLibs` to false: the loader maps them straight out of
     * the APK. Turning legacy packaging on would compress them — a smaller APK to
     * download — and then have the installer decompress a second copy into
     * /data/app on the device, which is slower to install and roughly doubles the
     * on-device footprint. Smaller file, worse app.
     */
    splits {
        abi {
            isEnable = true
            reset()
            include(*supportedAbis.toTypedArray())
            isUniversalApk = false
        }
    }

    defaultConfig {
        // Note: iOS uses com.bittr.bittr-regtest for the regtest variant. Android
        // applicationIds cannot contain hyphens, so the regtest build is
        // com.bittr.android.regtest. The flows hardcode that id today; unifying the
        // two platforms behind ${APP_ID} is BIT-7, once there is more than one
        // Android flow to unify. See shared/flows/android/README.md.
        //
        // Changing this value or the debug applicationIdSuffix below also requires
        // updating APP_ID in .github/workflows/android-maestro.yml, the `appId:` in
        // the workflow's APP_ID (which Maestro receives as --env APP_ID), and BiometricUnlockFlagTest,
        // which keys the regtest assertion off the applicationId rather than the
        // build type.
        //
        // It also requires re-registering the app in Firebase (BIT-39). The two
        // google-services.json files in src/debug/ and src/release/ are keyed by
        // package name and cannot simply be edited — the mobilesdk_app_id is issued
        // against the name. GoogleServicesConfigTest fails on the mismatch.
        applicationId = "com.bittr.android"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // Whether unlock may show BiometricPrompt (DEV-17) before the PIN pad.
        // On by default — the shipped app follows Android convention. The debug
        // build overrides it to false; see below.
        buildConfigField("boolean", "BIOMETRIC_UNLOCK_ENABLED", "true")

        // Which chain this build accepts addresses and invoices on, consumed via
        // core.common.destination.BitcoinNetwork. Mainnet by default; the debug
        // build overrides it below, exactly as iOS does
        // (`isDevelopment ? .regtest : .bitcoin`).
        buildConfigField("String", "BITCOIN_NETWORK", "\"MAINNET\"")

        // iOS's EnvironmentConfig, as the five values :core:wallet-ldk needs to
        // build a node (BIT-126). Read at runtime through di/LdkEnvironmentConfig.
        //
        // Every one of them defaults to "" and **none of them may ever be given a
        // real default in this file**. That is not caution, it is the issue's
        // note as a build rule: never mainnet keys, never production node access,
        // never real funds. NoEmbeddedNodeCredentialsTest keeps the library
        // module clean of them; NoCommittedNodeCredentialsTest keeps this one
        // clean, and it reads this build file too, so a helpful default added
        // here fails the build rather than shipping.
        //
        // Supply them per build, either as Gradle properties — in
        // ~/.gradle/gradle.properties or on the command line, never in a
        // committed gradle.properties — or as environment variables:
        //
        //   ./gradlew :app:assembleDebug \
        //     -Pbittr.ldk.chainSourceUrl=... \
        //     -Pbittr.ldk.lightningNodeId=... \
        //     -Pbittr.ldk.lightningNodeAddress=...
        //
        //   BITTR_LDK_CHAIN_SOURCE_URL=... ./gradlew :app:assembleDebug
        //
        // An unconfigured build is the normal state of this repository and is not
        // an error: LdkEnvironmentConfig.fromBuildConfig() returns null and
        // di/WalletModule composes the seed-only wallet, which is exactly what
        // the app did before BIT-126. CI and Maestro run that build.
        ldkEnvironment.forEach { (name, value) ->
            buildConfigField("String", name, "\"$value\"")
        }
    }

    buildTypes {
        debug {
            // Debug == regtest, mirroring the iOS Debug build that produces
            // com.bittr.bittr-regtest. This is the build Maestro runs against.
            applicationIdSuffix = ".regtest"
            versionNameSuffix = "-regtest"
            isMinifyEnabled = false

            // Biometrics OFF in the build Maestro installs, so every flow lands on
            // the PIN pad regardless of what the emulator image has enrolled.
            //
            // 296 of the 329 takeScreenshot steps sit behind a PIN entry. A
            // BiometricPrompt appearing ahead of the PIN pad does not degrade the
            // suite, it collapses it — and early, so every downstream flow looks
            // independently broken. Enforced by BiometricUnlockFlagTest and
            // BiometricApiGuardTest; consumed via core.common.AuthCapabilities.
            buildConfigField("boolean", "BIOMETRIC_UNLOCK_ENABLED", "false")

            // Debug == regtest, so a mainnet address pasted into the Maestro build
            // is rejected at parse time rather than at broadcast time.
            buildConfigField("String", "BITCOIN_NETWORK", "\"REGTEST\"")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Debug-signed so `assembleRelease` stays runnable in CI. Real signing
            // config lands with the first distributable build, not with the scaffold.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    /*
     * K7 and K8's instrumented sources, compiled in only when this build has an
     * environment for them to measure (BIT-132).
     *
     * `src/androidTestRegtest/` holds the tests that require a running node and a
     * live private network — RegtestEnvironmentTest and what BIT-132 builds on it.
     * They are worth nothing on an unconfigured build, which is the normal state
     * of this repository: a clone, the `build` job, every Maestro run and the
     * existing `wallet-instrumented` job all produce one on purpose.
     *
     * WHY A SOURCE SET AND NOT A JUNIT ASSUMPTION
     *
     * An `@Assume` would leave those classes in every test APK and skip them at
     * run time, and `check-wallet-instrumented-results.py` treats ANY
     * `<skipped/>` as a failed run — deliberately, because a skipped test does
     * not fail a build and is therefore the quietest way for a suite to stop
     * measuring anything. So the assumption route makes BIT-132's first commit
     * turn a green job red for behaving correctly.
     *
     * WHY THE CONDITION IS `any` AND NOT `all`
     *
     * "Somebody supplied at least one value", not "the environment is complete".
     * A build that supplied four of the five compiles these tests IN and then
     * fails their `@Before`, naming the blank fields — which is the
     * "partially configured is not configured" case from LdkEnvironmentConfig.
     * Gate on completeness here and that build would instead compile the tests
     * out and go green having measured nothing, which is the failure mode the
     * whole of BIT-132 is about.
     *
     * WHAT PAYS FOR THE ROT RISK
     *
     * Sources nothing normally compiles break silently. The `build` job runs
     * `:app:compileDebugAndroidTestKotlin` with throwaway values specifically to
     * typecheck this directory on every push — see "Compile the regtest
     * instrumented sources" in .github/workflows/android-maestro.yml. Without
     * that step a nightly-only suite becomes a suite that is broken at night.
     */
    sourceSets.getByName("androidTest") {
        if (ldkEnvironment.values.any { it.isNotBlank() }) {
            kotlin.srcDir("src/androidTestRegtest/kotlin")
        }
    }

    buildFeatures {
        compose = true
        // Required for the buildConfigField calls above — AGP does not generate
        // BuildConfig unless asked.
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    testOptions {
        unitTests {
            // AppLaunchTest launches the real MainActivity under Robolectric, which
            // needs the merged manifest and resources — the activity resolves
            // @style/Theme.Bittr at attach time. Without this it fails before
            // reaching the composition.
            isIncludeAndroidResources = true

            // Where ScaffoldScreenshotTest writes its PNG. Passed in rather than
            // derived inside the test, because a unit test's working directory is
            // an AGP implementation detail and the whole value of that file is
            // being able to tell someone exactly where to find it.
            //
            // Per variant, and that matters: the androidComponents block below
            // enables the release unit tests too, so `./gradlew test` runs two Test
            // tasks — in parallel, by default. Pointed at one path they would race
            // to write the same PNG and could leave a torn file. They also render
            // different builds (the debug one is regtest), so one shared file would
            // be whichever won.
            all {
                val variant = it.name.removePrefix("test").removeSuffix("UnitTest")
                    .lowercase()
                    .ifEmpty { "debug" }
                it.systemProperty(
                    "bittr.screenshot.dir",
                    layout.buildDirectory.dir("screenshots/$variant").get().asFile.absolutePath,
                )

                // Whether this build was handed an LdkEnvironment from outside
                // the repository. False for every build CI makes and every build
                // a clone makes, which is the case LdkEnvironmentConfigTest
                // asserts about: with nothing supplied, the compiled BuildConfig
                // must carry no node credentials.
                //
                // Passed in rather than re-derived in the test, because the test
                // can see the compiled constants and cannot see where they came
                // from — and the difference between "blank because nobody
                // configured it" and "blank because someone configured it to
                // blank" is the whole assertion. A developer who does supply real
                // values gets the assertion skipped with a message rather than a
                // red build they would eventually delete the test to fix.
                it.systemProperty(
                    "bittr.ldk.configured",
                    ldkEnvironment.values.any { value -> value.isNotBlank() }.toString(),
                )

                // BIT-129. The two halves of the ABI decision, as AGP resolved them
                // rather than as this file appears to say — read off
                // `defaultConfig.ndk` and `splits` themselves, so a value set
                // somewhere else (a build type, a plugin, a second `ndk` block) is
                // visible to AbiPackagingGuardTest instead of hidden behind a
                // grep of this file that still looks right.
                //
                // A deleted block reaches the test as an empty string, which fails.
                // That is the case worth engineering for: the decision is about
                // what is NOT in the APK, and absent configuration produces a
                // bigger, more permissive APK that nothing else complains about.
                it.systemProperty(
                    "bittr.abi.filters",
                    defaultConfig.ndk.abiFilters.sorted().joinToString(","),
                )
                it.systemProperty(
                    "bittr.abi.splits",
                    splits.abiFilters.sorted().joinToString(","),
                )
                it.systemProperty(
                    "bittr.abi.universalApk",
                    splits.abi.isUniversalApk.toString(),
                )
            }
        }
    }
}

// AGP 9 only creates a unit-test component for the debug variant. `./gradlew test`
// still describes itself as "Run unit tests for all variants" and still goes green,
// so a test whose assertion is about the release build never runs and reports
// success — BiometricUnlockFlagTest asserts biometrics stay ON in the shipped
// build, and that half was silently dead until this was turned on.
// (AGP 9 replaced HasUnitTestBuilder.enableUnitTest with the hostTests map;
// `enableUnitTest` still exists as an interface but application variants no longer
// implement it, so it fails to resolve rather than deprecating.)
androidComponents {
    beforeVariants(selector().withBuildType("release")) { variant ->
        variant.hostTests[com.android.build.api.variant.HostTestBuilder.UNIT_TEST_TYPE]
            ?.enable = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core:common"))
    implementation(project(":core:designsystem"))
    // BIT-98: the dark-mode choice, read at the root before the first frame.
    implementation(project(":core:preferences"))
    implementation(project(":core:permissions"))
    implementation(project(":core:wallet"))
    // The only place the wallet implementation is named. BIT-6 swaps this line
    // (and the binding in di/WalletModule.kt) for :core:wallet-ldk.
    implementation(project(":core:wallet-stub"))
    // BIT-126: the node's host — the foreground service, the wallet's scope, and
    // the WalletService decorator that binds start/stop to NodeLifecycle. On the
    // graph whether or not this build has an LdkEnvironment, because the
    // <service> and its two permissions have to reach the merged manifest either
    // way; which WalletService is composed is decided at runtime in
    // di/WalletModule, not by which module is on the classpath.
    implementation(project(":core:wallet-ldk"))
    // BIT-93: the seed half of the wallet — real BIP-39 key material behind a PIN,
    // no funds. :core:wallet-seed is the pure-Kotlin logic, :core:wallet-keystore
    // the Android Keystore storage it is bound to in di/WalletModule.kt.
    implementation(project(":core:wallet-seed"))
    implementation(project(":core:wallet-keystore"))
    implementation(project(":feature:signup"))
    // BIT-98 — the navigational skeleton: Home in its no-funds state, and the
    // Settings tree hanging off its bottom bar.
    implementation(project(":feature:home"))
    implementation(project(":feature:settings"))
    implementation(project(":feature:scanner"))
    // The three Wave 1 read-only screens (BIT-99).
    implementation(project(":feature:value"))
    implementation(project(":feature:map"))
    implementation(project(":feature:academy"))

    // The map renderer moved to :feature:map with the map screen, as the note here
    // said it should when that screen landed (BIT-53 -> BIT-99). It still reaches
    // :app's manifest merge through that module, which is what keeps
    // LocationPrecisionGuardTest asserting something real: MapLibre's own AAR
    // declares ACCESS_FINE_LOCATION, and the `tools:node="remove"` line below is the
    // only reason the shipped APK does not ask for it.
    implementation(project(":core:lnurl"))
    implementation(project(":feature:signup"))
    implementation(project(":feature:website"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    // BIT-133 — the background wake. Only the messaging artefact, and the set is
    // the point the same way CameraX's is: the analytics and crash-reporting
    // members of the same family are on LocationEgressGuardTest's tripwire list,
    // and firebase-messaging depends on neither. Its POM names
    // firebase-measurement-connector, which is the empty interface such an SDK
    // would implement if one were present. (Those two ids are described rather
    // than written, because that test is a string scan over build files and a
    // comment naming them trips it — see libs.versions.toml.)
    //
    // What it adds to the *shipped* permission set is two: WAKE_LOCK and
    // com.google.android.c2dm.permission.RECEIVE. Its AAR declares four, and the
    // other two were already in the merge — POST_NOTIFICATIONS is the app's own
    // and ACCESS_NETWORK_STATE arrives from MapLibre. Measured against the
    // merged manifest rather than read off the docs, and pinned by
    // FcmWakeWiringTest so that a third arriving in a version bump is a red test
    // rather than a line on the Play listing nobody reviewed.
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.hilt.navigation.compose)
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)

    testImplementation(libs.junit)
    // Robolectric, so the launch path itself is covered on the JVM rather than only
    // on an emulator. Same set :feature:signup already uses, so this adds no new
    // artefacts to resolve — see AppLaunchTest.
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.ext.junit)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    // Deliberately NOT `testImplementation(ui-test-manifest)`, and the reason is
    // worth keeping because it is the obvious fix and it does not work (BIT-106).
    //
    // `ui-test-manifest` is what declares `androidx.activity.ComponentActivity`,
    // the bare activity a `createComposeRule()` launches. Adding it to
    // `testImplementation` does put that activity into
    // `packaged_manifests/releaseUnitTest/`, so the change looks correct — but
    // Robolectric never reads that file. `test_config.properties` also gives it
    // `android_resource_apk`, and with `isIncludeAndroidResources = true` set above
    // that APK wins. Its manifest comes from the MAIN variant
    // (`processReleaseManifestForPackage`), which no test-only configuration can
    // reach. Verified: with the dependency added, the release
    // `apk-for-local-test.ap_` still has no `ComponentActivity` in its string pool
    // and all 16 tests still failed identically.
    //
    // The two configurations that WOULD reach it — `releaseImplementation` or
    // `src/release/AndroidManifest.xml` — both put a bare exported activity in the
    // shipped APK, to fix a test. So `:app` tests go through `MainActivity`
    // instead; see ComposeRuleVariantGuardTest, which enforces that.
    // Line 193 stays: androidTest is debug-only and resolves through it correctly.

    // BackupExclusionTest is plain JUnit4 over `bmgr` — no Compose, no Espresso.
    // Declared explicitly rather than leant on transitively through ext-junit,
    // the same way :core:wallet-ldk declares it.
    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)

    // BIT-59. Test-only, and deliberately NOT the `implementation` line above:
    // the shipped app still binds :core:wallet-stub, and this must not be the
    // thing that quietly swaps the wallet implementation — that swap is BIT-6's
    // to make, in one reviewed line.
    //
    // BackupExclusionTest needs it because the property it proves is a property
    // of the *installed application* — its merged manifest, its data directory,
    // its package name under `bmgr`. A library module's own instrumented tests
    // run in a test APK built from the library's manifest, and :core:wallet-ldk
    // has none, so backup defaults to ENABLED there: the exact opposite of the
    // configuration under test. The test has to run inside :app, and it needs
    // WalletPaths and AndroidKeystoreBlobCodec to write the material it then
    // looks for in a backup set.
    androidTestImplementation(project(":core:wallet-ldk"))

    // BIT-133. FcmWakeTest drives `WalletService`'s suspending API from a plain
    // JUnit4 instrumented test and polls a `StateFlow`, so it needs coroutines
    // on the compile classpath. :core:wallet-ldk declares them `implementation`,
    // not `api`, so they do not arrive through the line above.
    androidTestImplementation(libs.kotlinx.coroutines.core)

    // BIT-135. FcmDeliveryTest asks Play services for this install's registration
    // token and reads FirebaseApp's resolved project id, so it needs
    // firebase-messaging on the TEST compile classpath. The `implementation` line
    // above puts it on the app's, and androidTest does not inherit that — which is
    // why `project(":core:wallet-ldk")` is repeated here too.
    //
    // It is the same BOM and therefore the same version, so this cannot become a
    // second Firebase on the device: the test APK and the app APK are installed
    // side by side and `FirebaseMessaging.getInstance()` in the test resolves the
    // APP's singleton, because instrumented tests run in the target application's
    // process. That is the whole reason the token can be obtained without a single
    // line of debug-only code in `main` — see FcmDeliveryTest's class comment.
    androidTestImplementation(platform(libs.firebase.bom))
    androidTestImplementation(libs.firebase.messaging)
}
