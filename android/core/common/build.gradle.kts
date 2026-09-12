plugins {
    alias(libs.plugins.kotlin.jvm)
}

// Pure Kotlin on purpose: TestIDs must be readable from unit tests, from the
// wallet modules, and from Compose UI without dragging in the Android SDK.
kotlin {
    jvmToolchain(17)
}

dependencies {
    // The destination parser is the reason this module has tests at all: it is the
    // one piece of Send that can be proven correct with no node, no camera and no
    // emulator, which is what let it land ahead of the wallet engine (BIT-6).
    testImplementation(libs.junit)
}
