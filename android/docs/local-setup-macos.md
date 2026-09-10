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

That `export` lasts only as long as the terminal you typed it in. Make it stick one
of two ways — either is enough, you don't need both.

**Either** put the export in your shell profile:

```sh
echo 'export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools' >> ~/.zshrc
echo 'export PATH="$ANDROID_HOME/platform-tools:$PATH"' >> ~/.zshrc
```

`sdkmanager` is on `PATH` from the Homebrew cask; `adb` is not. `smoke-consecutive.sh`
will find it via `ANDROID_HOME` if you skip the PATH line, but anything you type
yourself (`adb devices`, `adb install`) needs it.

**Or** write an `android/local.properties` file, which points Gradle at the SDK
without touching your environment. From the repo root:

```sh
printf 'sdk.dir=/opt/homebrew/share/android-commandlinetools\n' > android/local.properties
```

> **`sdk.dir=…` is the *contents* of that file, not a command.** Typing it at a shell
> prompt gets you `zsh: no such file or directory: sdk.dir=…`, because zsh reads
> `sdk.dir=/opt/...` as a program to run. Use the `printf` line above, then check it
> with `cat android/local.properties` — one line, no quotes, no `export`.

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

You want to look at the scaffold, not just watch a build succeed. Four routes,
cheapest first.

### 0. A PNG from the build — no emulator, no device, no IDE

`./gradlew test` already wrote one:

```text
app/build/screenshots/debug/scaffold-launch.png     # the regtest build Maestro runs
app/build/screenshots/release/scaffold-launch.png   # the shipped build
```

`ScaffoldScreenshotTest` renders the app on the JVM under Robolectric and encodes
the result. It is not a `@Preview` of one composable — it comes off `MainActivity`
through the same rule `AppLaunchTest` uses, so what you are looking at went through
the real Hilt graph, `@style/Theme.Bittr`, the nav start destination and the real
`BittrTheme` tokens. If the file is there, the app launched to produce it.

Two things it is not. It is **not a golden-image test** — nothing asserts pixels,
because cross-renderer image diffing is a classic flaky-suite generator and BIT-5's
"a flaky pass is a failure" cuts both ways. And font rasterisation under Robolectric
is not what a device draws, so read it for layout, colour and content, not for
kerning. Appearance on a device is what the emulator run and Maestro's own
`takeScreenshot` cover.

If the file is missing after a test run, capture was skipped rather than failed —
it depends on Robolectric's native graphics, and on a host where that library is
unavailable the test reports *skipped*. That is deliberate: a convenience that
turns `./gradlew test` red on someone's laptop would be a bad trade for a picture.
`./gradlew :app:testDebugUnitTest --tests '*ScaffoldScreenshotTest*' -i` shows why.

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

Use **two** images, not one. ATD is what Maestro/CI run against; it has no SystemUI,
so the window is black even when the app is running. To *look at* the scaffold you
want a normal AOSP image.

**To see the screen** (real SystemUI, no Play Services):

```sh
sdkmanager "system-images;android-34;default;arm64-v8a" "emulator"
avdmanager create avd -n bittr-preview -k "system-images;android-34;default;arm64-v8a" -d pixel_6
"$ANDROID_HOME/emulator/emulator" -avd bittr-preview -no-snapshot-save -noaudio -no-boot-anim -gpu host &

cd android && ./gradlew :app:installDebug
```

Pass **`-gpu host`**. `avdmanager create` writes `hw.gpu.enabled=no`; without host
GPU the framebuffer stays black on Apple Silicon even on a full AOSP image.

**For Maestro**, matching CI, keep the ATD AVD:

```sh
sdkmanager "system-images;android-34;aosp_atd;arm64-v8a" "emulator"
avdmanager create avd -n bittr-test -k "system-images;android-34;aosp_atd;arm64-v8a" -d pixel_6
"$ANDROID_HOME/emulator/emulator" -avd bittr-test -no-snapshot-save -noaudio -no-boot-anim -gpu host &

cd android && ./gradlew :app:installDebug
adb shell am start -n com.bittr.android.regtest/com.bittr.android.MainActivity
```

Those package/device names exist in Google's repository — `aosp_atd` and `default`
both ship arm64-v8a for API 34, and `pixel_6` is device id 44 in
`avdmanager list device`. Boot, install, and a visible scaffold on `default` have
been run on an M-series Mac. `scaffold_smoke.yaml` has passed locally — see the
next section. CI is still open.

`aosp_atd` is an Automated Test Device image — stripped AOSP, no Play Services, no
Google apps, **no SystemUI**. Home is `EmptyHomeActivity`. Faster to boot and far
less likely to have a background service wake up mid-flow, which is why CI uses it.
The app has no Play Services dependency yet.

Expect this WARNING on ATD with `-d pixel_6` and ignore it:

```text
WARNING | adb command '... cmd overlay enable-exclusive ... com.android.systemui' failed:
'/system/bin/sh: com.android.systemui: inaccessible or not found
/system/bin/sh: ---: inaccessible or not found'
```

The emulator is applying Pixel SystemUI skins onto an image that has no SystemUI.
The `---` lines are `cmd overlay list` output (STATE_MISSING_TARGET) getting pasted
into a shell command. Boot still completes (`adb devices` shows `device`); the
window stays black because there is nothing to composite. UIAutomator — and
therefore Maestro — can still see the Compose test IDs after `am start`.

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

**Verified on 2026-09-10**, on an Apple Silicon MacBook following this document:
`./gradlew :app:assembleDebug` succeeded, an emulator booted, and
`scaffold_smoke.yaml` passed. That was the first execution of this harness against a
real device in BIT-5's history, and it settles the question the whole scaffold was
resting on — see "What the first run proved" below. ATD's window stays black (no
SystemUI); use `bittr-preview` in section 2 if you want to see the pixels.

With an emulator up and the app installed (section 2 above):

```sh
curl -fsSL "https://get.maestro.mobile.dev" | MAESTRO_VERSION=2.10.0 bash
export PATH="$HOME/.maestro/bin:$PATH"

maestro test shared/flows/android/scaffold_smoke.yaml   # from the repo root
```

Pin `MAESTRO_VERSION` to match `.github/workflows/android-maestro.yml`. Unpinned, the
installer takes `releases/latest`, and Maestro moves under this — recent versions
route `takeScreenshot` output into the `--debug-output` bundle rather than writing it
relative to the working directory.

### What the first run proved

`testTagsAsResourceId`. Compose `testTag`s are invisible to Maestro's view hierarchy
unless `MainActivity` sets that flag, and it is the highest blast-radius line in the
Android tree: without it *every* `assertVisible: id:` on both suites fails while the
app looks perfectly normal on screen. Nothing on the JVM could ever close it —
Robolectric reads the Compose semantics tree directly, so `AppLaunchTest` passes
identically with the flag on or off (mutation-tested, and it does). The guard on it
is a source check precisely because no test could be written that fails when it goes.

A green Maestro run is the only instrument that can observe the bridging, because
Maestro resolves `id:` against the accessibility tree the flag writes into. So the
pass is not just "the scaffold works" — it is the one piece of evidence that the
1,000-odd `id:` selectors across `shared/flows/**` will resolve on Android at all.

Still open after it: everything about *CI*. A local pass says the app and the flow
agree; it says nothing about AVD caching, emulator boot on a runner, or artefact
upload. And one pass is not three.

### Three consecutive runs, with the wall-clock number

BIT-5 closes on green runs *in a row*, plus a number — and a single manual
`maestro test` gives neither, because nobody times a manual run and one pass cannot
tell a working harness from a lucky one.

```sh
android/scripts/smoke-consecutive.sh          # 3 runs, per-run wall clock, no retries
android/scripts/smoke-consecutive.sh -n 10    # if you suspect a flake
```

It runs the flow N times against the booted device, times each, and prints a table.
It does not stop at the first red — finishing tells you "1 red in 3", which is the
answer to a flakiness question, where stopping only tells you "it broke". There are
deliberately no retries: a flow that needs one to pass is a failing flow. If the
slowest run is more than twice the fastest it says so, because an unstable number is
not a number worth quoting even when every run is green.

This measures the flow on your hardware, not CI — CI's own figure is decomposed into
boot/install/flow in each run's job summary.

The flow launches the app, waits for `core.launchComplete`, and asserts the three
signup test IDs are visible. It asserts the same IDs the iOS flow does, deliberately.

## If the build fails

| Symptom | Cause |
|---|---|
| `failed to find package platforms;android-37` | You dropped the `.0`. It's `platforms;android-37.0`. |
| `SDK location not found` | `ANDROID_HOME` unset and no `local.properties`. |
| `adb is not on PATH` | `ANDROID_HOME` unset, or `platform-tools` not on `PATH`. `export PATH="$ANDROID_HOME/platform-tools:$PATH"` — Homebrew's cask puts `sdkmanager` on `PATH`, not `adb`. |
| `zsh: no such file or directory: sdk.dir=/opt/...` | You pasted a *file's contents* at the shell prompt. `sdk.dir=…` goes inside `android/local.properties` — see the `printf` line in "Install". |
| Gradle can't find a project / "no build file" | You opened the repo root. The Gradle build root is `android/`. |
| Studio wants to downgrade AGP | Studio is older than AGP 9.4. Update Studio; do not downgrade AGP. |
| `PANIC: Broken AVD system path` | Launch the emulator as `"$ANDROID_HOME/emulator/emulator"`, not bare `emulator`. |
| Emulator boots but is glacial | x86_64 image on Apple Silicon. You want `arm64-v8a`. |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | Same thing from the other direction — arm64 device, x86_64-only APK, or vice versa. |
| `cmd overlay enable-exclusive` / `com.android.systemui: inaccessible or not found` | ATD + `-d pixel_6`. Harmless. The window is black because ATD has no SystemUI — use the `default` image in section 2 to see pixels. |
| Emulator window is black, `adb devices` shows `device` | Same ATD trap, or GPU off. Launch with `-gpu host`, or switch to `bittr-preview`. On ATD, `adb shell am start -n com.bittr.android.regtest/com.bittr.android.MainActivity` still brings the activity up for Maestro. |
| `element not found` in a Maestro flow | Usually `testTagsAsResourceId` removed from `MainActivity.kt` — see `../README.md`. |
