plugins {
    alias(libs.plugins.kotlin.jvm)
}

// Pure Kotlin, deliberately. Everything in here is a decision about whether a
// Lightning flow may proceed, and those decisions must be testable on the JVM
// without an emulator in the loop — see BIT-33 §Acceptance items 5 and 6, which
// are unit tests over exactly this module.
//
// It also keeps the module honest: with no Android SDK on the classpath there is
// no way to reach a WebView, a network client or a dialog from here. The policy
// cannot quietly start doing I/O.
kotlin {
    jvmToolchain(17)
}

dependencies {
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    implementation(libs.kotlinx.coroutines.core)
}
