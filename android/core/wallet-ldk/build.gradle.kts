plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

// The real wallet layer: ldk-node + BDK, Android Keystore key handling, and the
// LDK state quarantine guard.
//
// This is an Android library rather than a pure-Kotlin module because three
// things here genuinely need the platform: Keystore, the credential-encrypted
// data directory, and the ldk-node/BDK AARs (which ship native code).
//
// Everything that decides whether a user keeps their funds — blob
// classification, the seed discriminator, the quarantine guard — is written so
// it can be exercised without a device. That is deliberate. The emulator is the
// scarcest resource on this port (BIT-5: one self-hosted runner), and a rule
// that can only be checked on an emulator is a rule that gets checked rarely.
android {
    namespace = "com.bittr.android.core.wallet.ldk"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    api(project(":core:wallet"))

    // The funds-bearing dependencies. Versions are pinned in libs.versions.toml
    // against what iOS runs and asserted by WalletDependencyLockTest.
    implementation(libs.ldk.node.android)
    implementation(libs.bdk.android)

    implementation(libs.kotlinx.coroutines.core)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.ext.junit)
    testImplementation(libs.kotlinx.coroutines.test)

    androidTestImplementation(libs.androidx.test.ext.junit)
}
