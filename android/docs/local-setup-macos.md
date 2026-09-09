# Building the Android app on a Mac

What to install, in order, to get `./gradlew :app:assembleDebug` green on a MacBook.

**What exists right now:** a scaffold. One screen with three widgets (a "bittr"
header, a Create wallet button, a Restore wallet button), a navigation graph with
one route, a DI graph, a theme, and a stubbed wallet interface. No feature code, no
wallet, no network. Building it successfully gets you that screen and nothing more —
which is the point of BIT-5: prove the harness before there is anything to break.

## Requirements at a glance

| Thing | Version | Why this exact one |
|---|---|---|
| JDK | **17 or newer** to launch Gradle | AGP 9.4 requires JDK 17 minimum. You do *not* need to install 17 specifically — see below. |
| Android SDK platform | **`platforms;android-37.0`** | `compileSdk = 37`. Note the `.0` — see the trap below. |
| Android SDK build-tools | **`build-tools;36.0.0`** or newer | AGP 9.4's minimum and default. |
| Gradle | 9.7.1 | Comes from the wrapper in this repo. Don't install Gradle. |
| Android Studio | optional | Not needed to build. See "Studio" below. |

Versions live in `android/gradle/libs.versions.toml`. That file is authoritative;
this table is a convenience copy and can go stale.

### You do not need to install JDK 17 specifically

`settings.gradle.kts` enables the foojay toolchain resolver, and the pure-Kotlin
modules declare `jvmToolchain(17)`. So Gradle downloads its own Temurin 17 into
`~/.gradle/jdks/` and compiles with that, whatever JDK you launched it with. This is
verified, not theoretical: the build referenced below ran on a JDK 21 host and
Gradle auto-provisioned Temurin 17.0.20.1 for the toolchain modules.

You need *a* JDK ≥ 17 on `PATH` only so `./gradlew` can start.

## Install

```sh
# A JDK to launch Gradle with. 21 is a fine choice; 17 works too.
brew install --cask temurin@21

# The SDK. This is the command-line SDK only — no IDE.
brew install --cask android-commandlinetools
```

Then the SDK packages. Homebrew puts `sdkmanager` on `PATH` and installs into
`/opt/homebrew/share/android-commandlinetools` on Apple Silicon:

```sh
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
sdkmanager --licenses                       # accept them all
sdkmanager "platforms;android-37.0" "build-tools;36.0.0" "platform-tools"
```

Put `ANDROID_HOME` in your shell profile, or create `android/local.properties`:

```
sdk.dir=/opt/homebrew/share/android-commandlinetools
```

`local.properties` is gitignored (`.gitignore:105`) and must stay that way — it is a
machine-specific absolute path, and committing it breaks the build for everyone whose
SDK lives somewhere else.

### The `android-37.0` trap

The SDK package is `platforms;android-37.0`, **not** `platforms;android-37`. Android
moved to minor SDK versions, so the API level itself now carries a minor component —
`android-36`, `android-36.1`, `android-37.0`, `android-37.1`, `android-37.2` are all
distinct packages in Google's repository. `sdkmanager "platforms;android-37"` fails
with a "failed to find package" error that reads like the platform doesn't exist.

`compileSdk = 37` in the version catalog resolves to the `android-37.0` directory.

## Build

```sh
cd android
./gradlew test                  # JVM unit tests, all modules
./gradlew :app:assembleDebug    # debug == the regtest variant
```

APK lands at `app/build/outputs/apk/debug/app-debug.apk`.

Run `test`, not `testDebugUnitTest` — `:core:common`, `:core:wallet` and
`:core:wallet-stub` are pure-Kotlin modules with no Android variants, so
`testDebugUnitTest` reports `NO-SOURCE` for them and goes green having run nothing.

**First build will be slow** — Gradle downloads the whole dependency graph plus a
JDK. Budget 5–15 minutes depending on your connection. After that it is fast; a
clean rebuild with a warm dependency cache measured **1m09s** (Linux x86_64, JDK 21
host, `--no-daemon`, 195 tasks, 19 tests). Your first run will not look like that
number and that is expected.

## Studio

You do not need Android Studio to build this, and the command-line path above is the
one that has actually been verified. If you want the IDE:

```sh
brew install --cask android-studio
```

Current stable is Android Studio Quail (2026.1.x). AGP here is 9.4.0, and Studio
refuses to open a project whose AGP is newer than it supports — if Studio offers to
"upgrade" or complains about the AGP version, that is a Studio-too-old problem, not a
repo problem. Do not accept an AGP downgrade prompt: AGP 9 is load-bearing because
Hilt's Gradle plugin dropped AGP 8 at 2.59, and Hilt is the DI container.

## Running the Maestro flow locally

**Nothing below this line has been executed yet — not locally, not in CI.** The
agent environment this scaffold was built in has no `/dev/kvm`, so no emulator has
ever booted against this app. Treat this section as instructions to try, not as a
verified procedure.

On Apple Silicon you need the **arm64** system image. CI uses
`system-images;android-34;aosp_atd;x86_64`; the same image exists for arm64 and that
is the one to use on an M-series Mac — the x86_64 image runs under full CPU
emulation and is unusably slow:

```sh
sdkmanager "system-images;android-34;aosp_atd;arm64-v8a" "emulator"
avdmanager create avd -n bittr-test -k "system-images;android-34;aosp_atd;arm64-v8a" -d pixel_6
emulator -avd bittr-test -no-snapshot-save -noaudio -no-boot-anim &
```

`aosp_atd` is an Automated Test Device image — stripped AOSP, no Play Services, no
Google apps. Faster to boot and far less likely to have a background service wake up
mid-flow. The app has no Play Services dependency yet.

Then:

```sh
curl -fsSL "https://get.maestro.mobile.dev" | MAESTRO_VERSION=2.10.0 bash
export PATH="$HOME/.maestro/bin:$PATH"

cd android && ./gradlew :app:installDebug && cd ..
maestro test shared/flows/android/scaffold_smoke.yaml
```

Pin `MAESTRO_VERSION` to match `.github/workflows/android-maestro.yml`. Unpinned, the
installer takes `releases/latest`, and Maestro moves under this — recent versions
route `takeScreenshot` output into the `--debug-output` bundle rather than writing it
relative to the working directory.

The flow launches the app, waits for `core.launchComplete`, and asserts the three
signup test IDs are visible. It asserts the same IDs the iOS flow does, deliberately.

## If the build fails

| Symptom | Cause |
|---|---|
| `failed to find package platforms;android-37` | You dropped the `.0`. It's `platforms;android-37.0`. |
| `SDK location not found` | `ANDROID_HOME` unset and no `local.properties`. |
| Studio wants to downgrade AGP | Studio is older than AGP 9.4. Update Studio; do not downgrade AGP. |
| `element not found` in a Maestro flow | Usually `testTagsAsResourceId` removed from `MainActivity.kt` — see `../README.md`. |
