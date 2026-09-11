plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.bittr.android.feature.website"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        // For BuildConfig.DEBUG, which gates setWebContentsDebuggingEnabled in
        // HardenedWebView. A library module's own BuildConfig is used rather than
        // :app's (which feature modules cannot see) because DEBUG is a property of
        // the build type and matches across the two. Contrast AuthCapabilities,
        // which is injected — that one keys off the regtest applicationId, not the
        // build type, so it cannot be read from a library's BuildConfig.
        buildConfig = true
    }

    testOptions {
        unitTests {
            // Robolectric needs the merged manifest and resources; the top bar
            // resolves two drawables and two strings at composition time.
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
    implementation(project(":core:lnurl"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    // NOTE: androidx.webkit is deliberately absent, and its absence is a control
    // rather than an oversight (R-3). It is the artefact that provides
    // WebViewCompat.addWebMessageListener — the only bridge API this app would be
    // permitted to use — and no bridge ships in v1. Adding the dependency is
    // therefore the visible first line of any diff that adds one, which is where
    // the origin-allowlist review belongs. FirstPartyOrigins.allowedOriginRules is
    // waiting for it.

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.ext.junit)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    // The isolation tests (BIT-33 §Acceptance 3 and 4) need a real WebView with a
    // real renderer: they load a page on a non-allowlisted origin that both posts
    // to a message listener and navigates to lightning:lnurl1…, and assert that
    // nothing happens. Robolectric's WebView is a shadow with no JavaScript engine,
    // so it cannot answer that question either way — which would be worse than not
    // asking, because the test would pass.
    // Same set :app declares, so this adds no new artefacts to resolve — the
    // instrumentation runner named in defaultConfig arrives with espresso-core.
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
}
