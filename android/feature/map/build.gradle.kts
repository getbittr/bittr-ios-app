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

            // Where OnePlaceNameFitTest writes its PNGs. Same arrangement as :app,
            // :feature:scanner and :feature:value — passed in rather than derived in
            // the test, because a unit test's working directory is an AGP
            // implementation detail and the value of these files is being able to
            // tell someone where they are.
            all {
                it.systemProperty(
                    "bittr.screenshot.dir",
                    layout.buildDirectory.dir("screenshots").get().asFile.absolutePath,
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

// **What `SharedStringsTest` reads, said out loud to Gradle (BIT-113).**
//
// That test opens `shared/strings/en.json` by path at runtime. The file is
// outside the Gradle root entirely — it belongs to neither platform — so it
// cannot become an input to this task by accident the way a Kotlin source can.
// Without this, editing the canonical copy leaves every input of
// `testDebugUnitTest` untouched: Gradle calls the task up-to-date, or CI hands
// it back from the build cache, and the drift check does not run. The workflow's
// `paths:` filter lists `shared/strings/**`, so the job starts — and then
// verifies nothing, which is the worst of the three outcomes because it looks
// like the most.
//
// The directory rather than the one file: `shared/strings/README.md` is what
// says these copies are kept in step by hand, and a second locale landing there
// should re-run this without anyone remembering to widen a path.
tasks.withType<Test>().configureEach {
    inputs.dir(layout.projectDirectory.dir("../../../shared/strings"))
        .withPathSensitivity(PathSensitivity.RELATIVE)
        .withPropertyName("sourcesReadAtRuntime")
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
