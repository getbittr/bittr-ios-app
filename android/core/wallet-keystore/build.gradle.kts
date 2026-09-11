plugins {
    alias(libs.plugins.android.library)
}

// The Android side of the SecureStore seam: a Keystore-wrapped blob store.
//
// Kept to one class on purpose. Everything that can be decided without Android —
// what the words are, whether the PIN is right, what state the wallet is in — is in
// :core:wallet-seed, where it is tested on the JVM. What is left here can only run
// on a device, so what guards it is a source-level guard test in :app
// (KeystoreKeySpecGuardTest) plus BIT-18's on-device verification.
android {
    namespace = "com.bittr.android.core.wallet.keystore"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    api(project(":core:wallet"))
}
