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

// The two user settings that outlive a process and are read from more than one
// screen: the dark-mode choice and the display currency. Deliberately not part of
// the wallet seam — neither is wallet state, and putting them there would mean
// BIT-6 owning a preference the Device screen writes. iOS keeps them in
// CacheManager alongside wallet data; that conflation is not worth porting.
include(":core:preferences")
// The runtime-permission seam. Holds the permission set the app is allowed to ask
// for and the settings deep links the permanently-denied states navigate to — both
// of which approved copy makes factual claims about (BIT-57). Feature modules ask
// through here rather than naming permission strings directly, so the guard tests
// in :app have one allowed call site to check against.
include(":core:permissions")

// The wallet seam. :core:wallet is API-only (pure Kotlin interfaces + models).
// :core:wallet-stub is the deterministic implementation the scaffold and CI run
// against. BIT-6 adds :core:wallet-ldk (ldk-node + BDK) as a second binding of
// the same API; nothing above this line changes when it lands.
include(":core:wallet")
include(":core:wallet-stub")
// The real binding: ldk-node + BDK, plus the seed storage and LDK-state
// quarantine model decided in BIT-8 and BIT-20. See core/wallet-ldk/README.md.
include(":core:wallet-ldk")

// The seed, split along the line that makes it testable: :core:wallet-seed is pure
// Kotlin (BIP-39, the PIN verifier, the state machine) and runs on the JVM;
// :core:wallet-keystore is the Android-only half that seals the blobs with a
// Keystore key. BIT-93 — a real seed, no funds. Funds are BIT-6.
include(":core:wallet-seed")
include(":core:wallet-keystore")

// Features — one module per area of the iOS app, added as the port reaches them.
include(":feature:signup")

// BIT-98 — the navigational skeleton. :feature:home is the Home shell in its
// no-funds state (ios/bittr/Home); :feature:settings is the Settings pop-up, the
// Device-details rows, the website pages and the Lightning question card
// (ios/bittr/Settings, ios/bittr/Question).
include(":feature:home")
include(":feature:settings")
// The QR scanner (iOS S-16, ScannerViewController). Its own module so the CameraX
// dependency has exactly one place it can be reached from: the shipped claim that
// nothing is recorded is a property of the use cases this module binds, and a module
// boundary is what keeps "which code can touch the camera" answerable by reading one
// build file. See CameraCaptureGuardTest in :app.
include(":feature:scanner")

// The Bitcoin value / price chart (iOS ValueViewController). BIT-99, Wave 1.
include(":feature:value")

// The Bitcoin map (iOS Map/). BIT-99, Wave 1. Owns the MapLibre dependency and the
// BTCMap sync: both are constrained by approved copy rather than by taste — the
// renderer choice is BIT-53's and the whole-dataset sync is what makes the shipped
// "your location is never sent" true — so having one module boundary around them is
// what keeps "which code can reach the map stack" answerable from one build file.
// See MapSdkGuardTest and LocationEgressGuardTest in :app.
include(":feature:map")

// The Academy (iOS Academy/). BIT-99, Wave 1. Read-only content plus the lesson
// unlock rule; no wallet, no network beyond the six lesson images.
include(":feature:academy")
