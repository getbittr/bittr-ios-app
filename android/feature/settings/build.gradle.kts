plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

android {
    namespace = "com.bittr.android.feature.settings"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    // No `testOptions` block: this module has no `src/test`. The Settings tree is
    // covered by SettingsFlowTest in :app, which walks it through the shipping nav
    // graph against a real AppPreferences — the wiring that can actually break,
    // and which this module cannot see. See the dependencies block for why an
    // empty test configuration is not free.
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core:common"))
    implementation(project(":core:designsystem"))
    implementation(project(":core:preferences"))
    // The seam, for the rows that report node facts. No implementation is named.
    implementation(project(":core:wallet"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    // For the notification-permission launcher behind the Device-token row, which is
    // the Android half of iOS's `askForPushNotifications()`.
    implementation(libs.androidx.activity.compose)

    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.hilt.navigation.compose)
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)

    // No `testImplementation` lines, deliberately — this module has no `src/test`.
    // Under Gradle 9 a test dependency without a test is not inert: it puts
    // classes on the unit-test runtime classpath, so the Test task counts as
    // having sources, discovers nothing, and FAILS with "There are test sources
    // present ... but the test task did not discover any tests to execute". That
    // held the `./gradlew test` CI gate red on android-parity, together with
    // :core:preferences and :feature:home. Add them back with the tests.
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
