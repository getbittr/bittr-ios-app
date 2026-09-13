plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
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
}
