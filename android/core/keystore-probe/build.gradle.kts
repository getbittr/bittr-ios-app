plugins {
    alias(libs.plugins.android.library)
}

// BIT-18/K1 — the Keystore lock-screen-mutation probe and its harness.
//
// Nothing depends on this module and it is not in :app's dependency list, on purpose. It exists
// to hold an instrumented experiment: does a non-auth-bound AES/GCM Keystore key still open its
// blob after the user changes their lock screen? BIT-8 rule 2 says yes on the strength of AOSP
// javadoc; K1 turns that into a per-device fact.
//
// Driven by android/scripts/k1-lockscreen-matrix.sh, which needs the two phases as separate
// `am instrument` invocations with an adb-driven mutation in between — so `connectedAndroidTest`
// on its own does NOT produce a K1 result. It will run both phases back to back with no mutation
// between them, and phase 2 will fail its start-state assertion rather than report a false pass.
android {
    namespace = "com.bittr.android.core.keystore.probe"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    testImplementation(libs.junit)

    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.ext.junit)
    // Explicit rather than transitive: this module has no Espresso and no Compose test
    // dependency to drag the runner in behind it, and `testInstrumentationRunner` above names
    // a class that has to be on the androidTest classpath.
    androidTestImplementation(libs.androidx.test.runner)
}
