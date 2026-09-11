plugins {
    alias(libs.plugins.kotlin.jvm)
}

// Pure Kotlin on purpose: TestIDs must be readable from unit tests, from the
// wallet modules, and from Compose UI without dragging in the Android SDK.
kotlin {
    jvmToolchain(17)
}
