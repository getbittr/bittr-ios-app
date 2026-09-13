plugins {
    alias(libs.plugins.kotlin.jvm)
}

// Seed creation and the wallet state machine.
//
// Pure Kotlin on purpose. Everything that decides whether a wallet exists, whether
// a PIN is right and what the twelve words are lives here, where it runs on the JVM
// in milliseconds and needs neither an emulator nor Robolectric. The Android-only
// part — wrapping the blobs with a Keystore key — is the other side of the
// SecureStore seam, in :core:wallet-keystore.
//
// BIT-6 replaces neither of these: it adds :core:wallet-ldk for the funds side and
// composes with the seed this module produces.
kotlin {
    jvmToolchain(17)
}

dependencies {
    api(project(":core:wallet"))

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
