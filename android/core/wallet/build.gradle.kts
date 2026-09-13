plugins {
    alias(libs.plugins.kotlin.jvm)
}

// The wallet seam.
//
// This module is API-only and deliberately has no Android and no ldk-node/BDK
// dependency. Everything above it (app, features) compiles against these types
// alone, so swapping the implementation is a DI change, not a refactor.
//
// BIT-6 adds :core:wallet-ldk implementing WalletService against ldk-node +
// BDK. The API below is a scaffold placeholder sized to what the harness needs
// today — the Bitcoin Wallet Engineer owns its real shape and should widen it
// there rather than treating this as settled.
kotlin {
    jvmToolchain(17)
}

dependencies {
    api(libs.kotlinx.coroutines.core)

    // Interfaces cannot be tested, but PinLockout is not an interface: it is the pair
    // of numbers that decide when a wrong PIN erases someone's wallet, and it lives
    // here because both the implementation and the UI have to agree on them.
    testImplementation(libs.junit)
}
