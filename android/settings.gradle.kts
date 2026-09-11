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

// The LNURL decision layer (BIT-33). Pure Kotlin and deliberately so: everything
// in it decides whether a Lightning flow may proceed, and with no Android SDK on
// its classpath it cannot reach a WebView, an HTTP client or a dialog. It is
// shared by Send and by the in-app browser, which is exactly the sharing that
// makes LnurlSource necessary — see the class comment there.
include(":core:lnurl")

// The wallet seam. :core:wallet is API-only (pure Kotlin interfaces + models).
// :core:wallet-stub is the deterministic implementation the scaffold and CI run
// against. BIT-6 adds :core:wallet-ldk (ldk-node + BDK) as a second binding of
// the same API; nothing above this line changes when it lands.
include(":core:wallet")
include(":core:wallet-stub")

// Features — one module per area of the iOS app, added as the port reaches them.
include(":feature:signup")

// S-36 · Website — the in-app browser (BIT-33 / DEV-56). One chrome for all five
// iOS call sites, including the one handed an arbitrary URL from BTCMap place
// data. No LNURL bridge is attached on any origin; androidx.webkit is not a
// dependency of it, so the bridge API is not on the classpath at all.
include(":feature:website")
