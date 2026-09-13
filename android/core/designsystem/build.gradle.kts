plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.bittr.android.core.designsystem"
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
            // Same reason as `:feature:signup`: Robolectric needs the merged
            // resources and the manifest before `setContent` will inflate.
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
    // For TestID. BittrAlert applies the runtime-indexed `alert.button.N` tags
    // itself, the way iOS's AlertManager does, so no call site hand-interpolates
    // the number — see shared/test-ids/README.md.
    implementation(project(":core:common"))

    implementation(platform(libs.androidx.compose.bom))
    api(libs.androidx.compose.ui)
    api(libs.androidx.compose.ui.graphics)
    api(libs.androidx.compose.material3)
    api(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    // `TokenContrastTest` is arithmetic on the token values and needs none of this.
    // `CanvasComponentColorsTest` is the other half — whether a component *reads* the
    // token it is supposed to — and that needs a composition, because the colours are
    // assembled inside a `@Composable`. BIT-95: the defect was a call site, not a value,
    // and the pure-JVM guard could not have seen it.
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.ext.junit)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
