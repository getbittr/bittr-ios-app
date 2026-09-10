pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    // Lets Gradle download the JDK the build asks for (17, see the jvmToolchain
    // calls in the module build files) instead of using whatever JDK happens to
    // be on the machine. Without it the build only works on a host that already
    // has exactly the right JDK — which is how "green on CI, broken on my
    // laptop" starts.
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "bittr-android"

include(":app")

// Core — no feature knowledge, depended on by everything above it.
include(":core:common")
include(":core:designsystem")

// The wallet seam. :core:wallet is API-only (pure Kotlin interfaces + models).
// :core:wallet-stub is the deterministic implementation the scaffold and CI run
// against. BIT-6 adds :core:wallet-ldk (ldk-node + BDK) as a second binding of
// the same API; nothing above this line changes when it lands.
include(":core:wallet")
include(":core:wallet-stub")

// BIT-18/K1. An instrumented probe, not a shipped module — nothing depends on it. It proves on
// real devices what BIT-8 rule 2 currently asserts from AOSP javadoc: that a non-auth-bound
// Keystore key survives a lock-screen change. See android/docs/k1-keystore-lockscreen.md.
include(":core:keystore-probe")

// Features — one module per area of the iOS app, added as the port reaches them.
include(":feature:signup")
