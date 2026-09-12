plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
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
        // shared/flows/android/scaffold_smoke.yaml, and BiometricUnlockFlagTest,
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
