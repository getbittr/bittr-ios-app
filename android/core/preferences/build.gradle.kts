plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

android {
    namespace = "com.bittr.android.core.preferences"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // No `testOptions` block: this module has no `src/test`. AppPreferences is
    // exercised through :app (SettingsFlowTest drives the real Settings screens
    // over a real AppPreferences), which is where the behaviour that matters
    // actually lives. Declaring unit-test configuration for tests that do not
    // exist is what made `./gradlew test` fail — see the dependencies block.
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    // StateFlow only — no dispatcher work happens in this module, so `-core` is
    // the whole requirement and `-android` would add a Main dispatcher nothing here
    // uses.
    api(libs.kotlinx.coroutines.core)

    // No `testImplementation` lines, deliberately. This module has no `src/test`,
    // and under Gradle 9 a test dependency without a test is not inert: it puts
    // classes on the unit-test runtime classpath, so the Test task counts as
    // having sources, discovers nothing, and FAILS —
    //
    //   > Task :core:preferences:testDebugUnitTest FAILED
    //     There are test sources present and no filters are applied, but the test
    //     task did not discover any tests to execute.
    //
    // That took `./gradlew test` — the CI gate — red on android-parity from the
    // moment this module landed, alongside :feature:home and :feature:settings.
    // It is invisible to the per-module task lines agents run locally, because a
    // module with no tests is not one anybody thinks to name.
    //
    // If this module gains a `src/test`, add the dependencies back with it.
}
