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

This has been run from a **pristine clone** of the branch — a fresh `git clone`,
no `local.properties`, nothing but `ANDROID_HOME` exported — specifically to prove
the checkout contains everything the build needs and nothing is quietly coming from
an untracked file on the author's disk. That is the failure this section would
otherwise hide from you.

## Seeing the screen

You want to look at the scaffold, not just watch a build succeed. Three routes,
cheapest first.

### 1. Android Studio's Compose preview — no emulator, no install

`SignupStartScreen.kt` carries a `@Preview`, so Studio renders the screen in the
right-hand pane without booting anything. Open `android/` as the project root (not
the repo root — the repo root has no Gradle build), let it sync, open
`feature/signup/src/main/kotlin/com/bittr/android/feature/signup/SignupStartScreen.kt`
and click **Split**.

This is by far the fastest way to answer "is the scaffold what I expected", and it
sidesteps every emulator problem below. It renders the real `BittrTheme`, so the
tokens are what you'll see. It does *not* prove the app launches — the preview
renders one composable, it doesn't run `MainActivity` or Hilt.

### 2. An emulator

On Apple Silicon you need the **arm64** system image. CI uses
`system-images;android-34;aosp_atd;x86_64`; the x86_64 image on an M-series Mac runs
under full CPU emulation and is unusably slow.

```sh
sdkmanager "system-images;android-34;aosp_atd;arm64-v8a" "emulator"
avdmanager create avd -n bittr-test -k "system-images;android-34;aosp_atd;arm64-v8a" -d pixel_6
"$ANDROID_HOME/emulator/emulator" -avd bittr-test -no-snapshot-save -noaudio -no-boot-anim &

cd android && ./gradlew :app:installDebug
```

Those three package/device names are **verified to exist** in Google's live
repository as of this commit — `aosp_atd` ships arm64-v8a for API 30 through 36, and
`pixel_6` is device id 44 in `avdmanager list device`. What is *not* verified is that
the emulator boots and the app runs on it: see the banner in the next section.

`aosp_atd` is an Automated Test Device image — stripped AOSP, no Play Services, no
Google apps. Faster to boot and far less likely to have a background service wake up
mid-flow. The app has no Play Services dependency yet.

**Launch the emulator by absolute path**, as above. `emulator` resolves on `PATH`
from the Homebrew cask, but launched from the wrong working directory it locates its
system images relative to the binary and dies with `PANIC: Broken AVD system path`
or `Cannot find AVD system path` — an error that reads like the AVD is corrupt when
the AVD is fine.

### 3. A physical phone

`./gradlew :app:installDebug` with USB debugging on works and skips the emulator
entirely. `adb devices` should list it before you install. Any phone on Android 8.0
or newer — `minSdk` is 26.

### What you should see

A centred column on a plain background: the word **bittr** in `headlineLarge`, a
filled **Create wallet** button, an outlined **Restore wallet** button, both full
width. The buttons do nothing — there is no wallet behind them. If you see that,
deliverables 1 and 2 are real and you have seen them with your own eyes.

The colours come from `core/designsystem`, transcribed from `ios/bittr/Colors.swift`.
BIT-4 replaces them with the Designer's tokens, so don't read the current palette as
a design decision.

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

**No emulator has ever booted against this app, and Maestro has never run against
it** — not locally, not in CI. The agent environment this scaffold was built in has
no `/dev/kvm`. Package names and flow syntax are verified; *behaviour* is not. Treat
this section as instructions to try, not as a verified procedure.

With an emulator up and the app installed (section 2 above):

```sh
curl -fsSL "https://get.maestro.mobile.dev" | MAESTRO_VERSION=2.10.0 bash
export PATH="$HOME/.maestro/bin:$PATH"

maestro test shared/flows/android/scaffold_smoke.yaml   # from the repo root
```

If you get this far, **that is the first real execution of the harness** and it is
the thing BIT-5 has been missing. Send me the output either way — a failure is more
useful to me than a pass, because the whole risk sitting in this task is the set of
assumptions no one has tested yet.

The most likely first failure is `element not found` on the test IDs: Compose
`testTag`s are only visible to Maestro's view hierarchy because `MainActivity` sets
`testTagsAsResourceId = true`. That wiring has a JVM test behind it, but a JVM test
proves the flag is set, not that Maestro reads it.

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
| Gradle can't find a project / "no build file" | You opened the repo root. The Gradle build root is `android/`. |
| Studio wants to downgrade AGP | Studio is older than AGP 9.4. Update Studio; do not downgrade AGP. |
| `PANIC: Broken AVD system path` | Launch the emulator as `"$ANDROID_HOME/emulator/emulator"`, not bare `emulator`. |
| Emulator boots but is glacial | x86_64 image on Apple Silicon. You want `arm64-v8a`. |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | Same thing from the other direction — arm64 device, x86_64-only APK, or vice versa. |
| `element not found` in a Maestro flow | Usually `testTagsAsResourceId` removed from `MainActivity.kt` — see `../README.md`. |
