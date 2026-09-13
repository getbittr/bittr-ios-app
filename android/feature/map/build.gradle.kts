plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.bittr.android.feature.map"
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

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core:common"))
    implementation(project(":core:designsystem"))
    // The map asks for location through here rather than naming a permission. There
    // is one approved location permission and it is coarse; BittrPermissions is the
    // single place in the repo allowed to spell it out (LocationPrecisionGuardTest).
    implementation(project(":core:permissions"))
    // A merchant's website opens in the app's one in-app browser, not in a WebView
    // this module builds. The copy that used to live here was created with
    // `WebView(context)` and platform defaults, which is what BIT-112 removed;
    // WebViewHardeningGuardTest fails the build if it comes back.
    implementation(project(":feature:website"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.coroutines.core)

    // The renderer. It lived on :app between BIT-53 and this issue so the manifest
    // guards had a real merge to assert against; the build file it was declared in
    // said to move it with the map screen, and this is that screen. Both guards read
    // every build file in the tree, so they follow it here without being edited —
    // and :app still merges MapLibre's manifest transitively, which is what
    // LocationPrecisionGuardTest's `tools:node="remove"` assertion depends on.
    api(libs.maplibre.android)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.ext.junit)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
