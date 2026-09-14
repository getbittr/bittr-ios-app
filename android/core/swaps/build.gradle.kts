plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin {
    jvmToolchain(17)
}

// Swaps between on-chain and Lightning through Boltz (ios/bittr/Swaps).
//
// Pure Kotlin, on the same line :core:network and :core:lnurl are drawn: every
// decision a swap makes with the user's money — the Taproot lockup it will fund,
// the checks on what Boltz answers, the MuSig2 claim and refund, the fee
// arithmetic, the file a swap is kept in — is here and runs as a JVM test. The
// wallet, the node, the socket and the screen are behind interfaces `:app`
// implements (SwapWallet, SwapStatusFeed, InvoiceInspector).
dependencies {
    api(project(":core:network"))

    // Taproot, MuSig2 and transactions. bitcoin-kmp's JNI half comes from the app
    // (secp256k1-kmp-jni-android via :core:wallet-ldk) and, for tests, from the
    // JVM artifact below.
    api(libs.bitcoin.kmp)

    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    // The JNI half of secp256k1 for host-side tests. It is published for JVM 21 only, so the
    // test runtime asks for 21 and the tests run on a 21 launcher; the main source set stays on
    // 17, which is what `:app` consumes.
    testRuntimeOnly(libs.secp256k1.jni.jvm)
}

configurations.named("testRuntimeClasspath") {
    attributes { attribute(TargetJvmVersion.TARGET_JVM_VERSION_ATTRIBUTE, 21) }
}

tasks.withType<Test>().configureEach {
    javaLauncher.set(javaToolchains.launcherFor { languageVersion.set(JavaLanguageVersion.of(21)) })
}
