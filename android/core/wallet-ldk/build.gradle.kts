plugins {
    // No `kotlin.android` alias: AGP 9 brings Kotlin support built in and
    // fails the build if the plugin is applied on top of it.
    alias(libs.plugins.android.library)
}

// The real binding of :core:wallet, against ldk-node + BDK (BIT-6).
//
// Layering rule inside this module, and the reason the tests below can run on
// the JVM at all: everything that decides *what to do with the user's funds*
// — the seed-import guard, the state discriminator, the quarantine path, the
// blob classification — is written against `java.io.File` and injected
// interfaces, with no ldk-node, BDK or Android Keystore type in its signature.
// Those types appear only in the adapters that sit at the edge.
//
// This is not tidiness. bdk-android and ldk-node-android are UniFFI wrappers
// over native `.so` files and the Android Keystore is a device service, so any
// decision expressed in terms of them is provable only on an emulator. The
// definition of done asks for a named test per claim; a claim whose test needs
// an emulator that CI does not have yet is a claim with no test.
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
            isReturnDefaultValues = false
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

    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.coroutines.core)

    // BIP39/BIP32 on the JVM. `api` because the account-xpub type is part of
    // the discriminator's surface.
    api(libs.bitcoin.kmp)
    implementation(libs.secp256k1.jni.android)

    // The native bindings. Nothing under `seed/`, `state/` or `bip/` may
    // reference these — see WalletLayeringGuardTest, which enforces it.
    implementation(libs.bdk.android)
    implementation(libs.ldk.node.android)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.ext.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    // The JNI half of secp256k1 for host-side tests. Without it every
    // derivation test fails at first use with an unsatisfied link error.
    testImplementation(libs.secp256k1.jni.jvm)

    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}
