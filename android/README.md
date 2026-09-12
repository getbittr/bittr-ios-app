# bittr Android

Native Android app — Kotlin + Jetpack Compose + Material 3.

**Status: scaffold, green in CI across three consecutive runs.** The project builds, the
unit tests pass, the DI graph resolves and navigation renders one screen. There is no
feature code and no wallet. See `../ANDROID_PORT_PLAN.md` for where this is going.

**The Maestro flow has run green on a real emulator** — 2026-09-10, on a MacBook
following `docs/local-setup-macos.md`. That closes the assumption the scaffold rested
on: Compose `testTag`s really are reachable by Maestro's `id:` selectors through
`testTagsAsResourceId`, which no JVM test can prove (Robolectric reads the semantics
tree directly and passes with the flag either way). Details in that doc under "What
the first run proved".

**Three consecutive local runs, green, no retries** — 2026-09-10, same MacBook,
via `scripts/smoke-consecutive.sh`:

| run | result | wall clock |
|-----|--------|------------|
| 1 | green | 12.1s |
| 2 | green | 10.9s |
| 3 | green | 10.4s |

Median 10.9s, spread 1.7s, total 33.7s. That is the flow itself against an already
booted emulator — it answers "is the flow reliable", not "how long does CI take",
which is a different question with an answer minutes away. Local Maestro was 2.5.1
against CI's pinned 2.10.0, so treat the numbers as comparable to each other and not
to a CI run; the script says so itself when it detects the skew.

**CI has now run green, end to end, on a GitHub-hosted runner** — the run for `a93f1fe`
built the APK, booted an emulator, installed the app and passed
`shared/flows/android/scaffold_smoke.yaml`. Every step of this workflow has now executed
successfully at least once; none of it is unexercised code any more.

The run before it was red, and is worth keeping on the record because the fix shaped the
workflow. It failed on the first line of its own script, after a full emulator boot:

```
/usr/bin/sh: 1: set: Illegal option -o pipefail
```

`reactivecircus/android-emulator-runner` runs its `script:` input under `/usr/bin/sh`
— dash on the Ubuntu images — not bash. The body is now `scripts/ci-smoke.sh`, called
as `bash <file>` so the interpreter is chosen by this repo rather than by whichever
image the runner happens to be, and `scripts/check-action-scripts.sh` fails the build
job in seconds if any `script:` input stops being POSIX.

## The wall-clock number

**Three consecutive green CI runs, 2026-09-10**, pushes to
`feature/bit-5-android-scaffold`. Read from the GitHub API, not copied off a page:

| run | commit | end-to-end | build job | emulator job | flow |
|-----|--------|-----------:|----------:|-------------:|-----:|
| 8 | `d2f1ba9` | 6m36s | 4m33s | 1m55s | 18s |
| 9 | `6a9bc95` | 6m37s | 4m13s | 2m17s | 20s |
| 10 | `4855ed2` | 6m42s | 4m34s | 2m00s | 19s |

**Median end-to-end 6m37s, spread 6s.** That is the number to quote: commit pushed to
run finished. Reproduce it any time with `scripts/ci-runs.py --require-green 3`.

The shape of that number is the surprising part, and it inverts the assumption this
whole task was built on. **The emulator is not the slow half.** It is about two
minutes, and it is stable to within 22 seconds across three runs. The long pole is the
`build` job at ~4m30s, of which **unit tests alone are 3m-3m26s** — roughly half of
total CI time, on a scaffold with eleven tests. That is where the time goes today, and
Gradle configuration/daemon warm-up rather than the tests themselves is the first thing
to look at if anyone decides 6m37s is too long to wait.

For the same reason, treat the `::notice` on a run page as the *emulator job's*
decomposition and not as the run's duration — it reports ~2 minutes while the run took
6m37s. `ci-runs.py` prints both, with the end-to-end figure first.

Two things had to change before three runs could even be attempted, both of which would
otherwise have quietly produced the wrong answer:

- **The three runs have to survive.** `workflow_dispatch` needs the workflow on the
  default branch, which it is not, so pushing is the only available trigger — and the
  concurrency group keyed pushes on the ref with `cancel-in-progress: true`, which would
  have cancelled runs 1 and 2. Non-dispatch runs are keyed on `github.sha` now. See
  `docs/self-hosted-runner.md`, *Why three runs in a row is safe to do*.
- **The number has to be readable.** The job writes a wall-clock table to the step
  summary, and after the first green run that number still did not reach the person who
  needed it — a step summary sits at the bottom of the run page behind a scroll. The same
  figures are now also emitted as a `::notice`, which renders at the top of the run page
  and is the first thing on screen when a run is opened.

  That still put a person in the loop, and the loop still leaked: three rounds of this
  issue ended with someone being asked to open the Actions tab and copy a line back.
  **`scripts/ci-runs.py` removes the person entirely** — this repo is public, and the
  Actions REST API on a public repo needs no authentication, so run results, per-step
  durations and annotations are all readable with one command and no token. The
  premise that they were unreadable was never checked.

## Build

```sh
cd android
./gradlew :app:assembleDebug        # debug == regtest variant
./gradlew test                      # JVM unit tests, all modules
```

Use `test`, **not** `testDebugUnitTest`. `:core:common`, `:core:wallet` and
`:core:wallet-stub` are pure-Kotlin modules with no Android variants, so
`testDebugUnitTest` reports `NO-SOURCE` for them and goes green having run a
fraction of the suite.

`test` also covers **`:app:testReleaseUnitTest`**, and that is the half most
easily lost. `:app` is the only module with a release unit-test component
(`androidComponents` in `app/build.gradle.kts`), and it is where the assertions
about the *shipped* build live — `BiometricUnlockFlagTest`'s biometrics-on
branch runs nowhere else.

This matters because `./gradlew --offline test` does **not** work: it fails
during configuration-cache serialisation on an uncached `lint-gradle` artifact,
before running a single test. The workaround is to name tasks —

```sh
./gradlew --offline :core:common:test :core:wallet:test :core:wallet-seed:test \
  :core:wallet-stub:test :core:designsystem:testDebugUnitTest \
  :feature:signup:testDebugUnitTest :feature:value:testDebugUnitTest \
  :feature:academy:testDebugUnitTest :feature:map:testDebugUnitTest \
  :feature:scanner:testDebugUnitTest \
  :app:testDebugUnitTest :app:testReleaseUnitTest
```

— and a hand-written list is exactly where a variant goes missing. Leaving
`:app:testReleaseUnitTest` off that line is what let BIT-97, BIT-100 and BIT-99
each close over 16 tests that had never passed (BIT-106). If you use the
offline line, keep the release task on it, and treat `./gradlew test` with a
network as the real answer.

Do not add a module with no `src/test` to that line, or to the build with
`testImplementation` dependencies: Gradle 9 fails a `Test` task that has a
non-empty test classpath and discovers nothing, which is a second way this gate
goes red without anyone touching a test.

Requires JDK 17+ and an Android SDK with `platforms;android-37.0` (`compileSdk = 37`
— note the `.0`, the API level carries a minor component now and `android-37` is not
a package that exists). Point Gradle at the SDK with `ANDROID_HOME`, or a
`local.properties` containing `sdk.dir=/path/to/sdk` (gitignored — never commit it).

Verified from a pristine `git clone` of this branch with no `local.properties` —
2m01s, 195 tasks, APK produced — so the checkout is self-contained.

Step-by-step for a Mac: `docs/local-setup-macos.md`. If you only want to *look* at
the scaffold screen, that doc's "Seeing the screen" section gets you there through
Android Studio's Compose preview without booting an emulator at all.

## Maestro

```sh
./gradlew :app:installDebug
maestro test ../shared/flows/android/scaffold_smoke.yaml
```

CI runs this on every push: `.github/workflows/android-maestro.yml`.

## Module structure

```
app                  single Activity, navigation graph, DI wiring
core/common          generated TestIDs.kt (pure Kotlin, no Android)
core/designsystem    BittrTheme + tokens
core/permissions     the permissions the app may request, and settings deep links
core/wallet          wallet API — interfaces and models only, no implementation
core/wallet-stub     deterministic no-op wallet, used by the scaffold and CI
feature/signup       create-or-restore entry point
feature/scanner      the QR scanner — the only module that may touch the camera
```

Dependencies point downward only: `feature/*` and `app` depend on `core/*`;
`core/*` never depends on a feature. Features do not depend on each other — anything
two features need belongs in `core`.

### The wallet seam

This is the part the structure exists for. `:core:wallet` is **API-only** — pure
Kotlin interfaces, no Android dependency, no ldk-node, no BDK. Everything above it
compiles against those types alone.

`:core:wallet-stub` is the implementation the scaffold and CI run against: no key
material, no disk, no sockets. That is deliberate. It means a red Maestro run has
exactly one cause (the app is broken) rather than eleven (node won't sync, regtest
is down, the channel didn't open).

BIT-6 adds `:core:wallet-ldk` as a second implementation of the same interface. The
switch is two lines — the dependency in `app/build.gradle.kts` and the binding in
`app/src/main/kotlin/com/bittr/android/di/WalletModule.kt`. **If it turns out to be
more than two lines, something upstream has taken a dependency on the
implementation instead of the interface, and that is the seam leaking.**

The interface in `:core:wallet` is sized to what the scaffold needs today and is
explicitly *not* a design for the wallet layer — the Bitcoin Wallet Engineer owns
that shape and should widen it in BIT-6.

## Permissions are copy, and the copy has been approved

Read `core/permissions/.../BittrPermissions.kt` before you write a permission
request. Three of the approved permission strings make **factual claims about what
this build does**, and compliance signed them off as binding on the implementation
rather than as preferences (BIT-36, BIT-57). All three are founder-approved copy as
of 2026-09-11 (BIT-15):

- *"The camera is used only to read the code in front of it. Nothing is recorded."*
  → the scanner binds CameraX `ImageAnalysis` and **no capture use case**.
- *"To centre the map on where you are, bittr needs your approximate location."*
  → `ACCESS_COARSE_LOCATION` only. Never fine.
- *"Your location is used on your device to position the map. It isn't sent to
  bittr."* → the fix may set the map region; it may not enter a request body or an
  analytics event.

Note what the third one does **not** say. It is not a claim that your location never
leaves the device — centring the map makes the renderer fetch tiles for the area
around you, and the Android renderer is still unchosen (BIT-52, BIT-53). Tile
fetching is allowed. Do not implement against *"stays on your device"* or *"never
shared with third parties"*; those are overclaims, and the broader version bittr
already ships on iOS is under separate review (BIT-45, BIT-56).

All three are enforced on the JVM, by `CameraCaptureGuardTest`,
`LocationPrecisionGuardTest` and `LocationEgressGuardTest`. Each checks three
places, because there are three ways to break a claim and only one of them is
visible in a diff:

1. **The Kotlin sources** — someone types the API.
2. **The build files** — a banned artefact arrives as a dependency.
3. **The merged manifest**, read back through Robolectric's `PackageManager` — a
   dependency declares the permission in *its* manifest and the merger unions it
   into the APK. No source scan can see this one, which is why
   `app/src/main/AndroidManifest.xml` carries `tools:node="remove"` entries for
   `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION` and `RECORD_AUDIO`. Those
   lines are load-bearing; do not delete them to make a build pass.

The scanner exists now (`feature/scanner`, BIT-72), so `CameraCaptureGuardTest` is
scanning a real camera call site rather than an empty tree. The two location guards
are still waiting on the map, and pass without examining a real offender.
`LocationEgressGuardTest` therefore also runs its detector against a synthetic
violation, so that a regression in the *detector* fails the build instead of quietly
disarming the guard while it keeps reporting green.

**These tests are not style rules, and passing them is not optional.** The failure
they catch is the one nothing else can: the app keeps working perfectly, every flow
stays green, and the only thing that changed is that a sentence bittr has shipped to
users stopped being true. If a screen genuinely needs a capture use case, precise
location, or the coordinate server-side, say so on BIT-57 *before* it ships — the
copy changes first, and changed copy goes back through compliance.

For the camera specifically, the sentence lives in one function:
`ScannerViewfinder` in `feature/scanner`, which is the only `bindToLifecycle` call
in the repo. It binds a viewfinder and an analyser. CameraX publishes two more use
cases — one for stills, one for video — and neither artefact is on the graph, so
adding one means editing a build file as well as a line of Kotlin. That is
deliberate: it makes the change visible in a diff twice.

The permanently-denied states have a requirement of their own: the approved copy no
longer names an OS settings path, so the button has to do the navigating. Use
`AppSettings` + `firstResolvable` rather than building the intent inline —
the fallback chain and the `<queries>` visibility declaration both live there, and
the second is invisible to every JVM test (`AppSettingsDeepLinkTest` guards it by
source).

## Test IDs

Do not hand-write test tags. `core/common/.../TestIDs.kt` is generated from
`shared/test-ids/test-ids.json` by `shared/test-ids/build.py`, which emits the Swift
and Kotlin constants from the same source so the Maestro flows see identical strings
on both platforms. Add the leaf to the JSON, run the generator, commit both
generated files. CI fails the build if they are stale.

Apply them with `Modifier.testTag(TestID.Signup.Create.Start.createWalletButton)`.

**`testTagsAsResourceId` is load-bearing.** Compose test tags are not visible to
UIAutomator — and therefore not to Maestro — unless `testTagsAsResourceId = true` is
set on an ancestor node. It is set once, on the root in `MainActivity.kt`. Delete it
and every `assertVisible: id:` in every flow fails with "element not found" while
the app renders perfectly on screen.

## Theme

`core/designsystem/.../Tokens.kt` holds the palette, currently transcribed from
`ios/bittr/Colors.swift` so the scaffold renders in Bittr's brand rather than
Compose's default purple. **These are iOS values, not an Android design system.**
BIT-4 replaces the contents of that one file; `Theme.kt` and every call site read
through the token names and do not change.

Material You dynamic colour is deliberately off — this is a brand-led financial app
with a fixed palette on iOS, and letting the wallpaper pick the accent would break
parity. Turning it on is a design decision for BIT-4, not a scaffold default.

Typography is Material 3's default. The iOS app ships Gilroy, Montserrat, Palanquin
and Syne (`ios/*.ttf`); which of those come across is BIT-4's call.

## Unlock, biometrics, and the test build

**`BiometricPrompt` must never appear in the build Maestro runs against.** This is
the single most load-bearing constraint on the scaffold, because PIN entry is the
deepest shared dependency in the suite: 28 flows call `helpers/unlock.yaml`, 7 tap
the PIN pad directly, and **296 of the 329 `takeScreenshot` steps — 90% — sit
behind a PIN entry**. A biometric prompt ahead of the PIN pad doesn't degrade the
suite, it collapses it, and it collapses it early enough that every downstream flow
looks independently broken.

Biometric unlock (DEV-17) is an Android-convention *addition*, not a port —
`shared/docs/parity.md` lists "no biometric / Face ID unlock" under *Confirmed
absent in iOS*. So no shared flow will ever exercise it, and it needs its own
Android-only test.

Three things enforce this, none of which depends on how the emulator image is
configured:

| Mechanism | What it catches |
|---|---|
| `BuildConfig.BIOMETRIC_UNLOCK_ENABLED` — `false` in debug, `true` otherwise | the flag itself |
| `core/common/.../AuthCapabilities.kt`, injected via `di/AuthModule.kt` | feature modules can't read `:app`'s `BuildConfig`, so this is the one binding to audit |
| `BiometricUnlockFlagTest`, `BiometricApiGuardTest` (`:app` unit tests) | the flag being flipped, and any use of `BiometricPrompt`/`BiometricManager` that doesn't route through the gate |

`BiometricApiGuardTest` is a **routing rule, not a ban** — shipping the prompt is
expected. Add the file to its `ALLOWED_FILES` once the call reads
`biometricUnlockEnabled` first. It is a text scan over `android/**.kt`, so it also
trips on the API names in comments; that conservatism is deliberate.

Note the emulator's own enrolment state is never consulted. If unlock ever asks
`BiometricManager.canAuthenticate()` before checking the gate, a CI image with a
fingerprint enrolled behaves differently from one without, and that difference is
exactly the flakiness this design exists to prevent.

### FLAG_SECURE will blank the whole screenshot suite if you set it app-wide

`FLAG_SECURE` is Android's answer to the iOS seed-phrase screenshot warning
(DEV-18). It is the right answer, and it is a **window** flag — this app has one
window. Set it in `MainActivity.onCreate` and it stays set for the session, so all
329 `takeScreenshot` steps capture black frames. They do not fail; Maestro is
perfectly happy to screenshot a black screen. CI stays green and the artefacts are
worthless.

Scope it to the screen that needs it — a `DisposableEffect` that adds the flag on
enter and clears it on dispose. `ScreenshotBlockingGuardTest` fails the build if it
appears in `MainActivity.kt` or `BittrApplication.kt`.

## Stack

- Kotlin 2.4.20, AGP 9.4.0, Gradle 9.7.1
- Jetpack Compose (BOM 2026.08.00) + Material 3
- minSdk 26 (Android 8.0) — full Keystore/biometric support, no legacy key-storage
  workarounds for the wallet layer
- compileSdk 37, targetSdk 36
- Hilt for DI, Coroutines/Flow
- Compose Navigation, single-Activity

Versions are pinned in `gradle/libs.versions.toml` — read that file rather than
this list. Two traps live there:

- **KSP no longer tracks the Kotlin version.** The scheme changed at KSP 2.3.0;
  it used to be `<kotlin>-<ksp>` (e.g. `2.2.21-2.0.5`) and is now independent.
  Don't go looking for a KSP release matching the Kotlin version — there isn't one.
- **AGP 9 is not optional.** Hilt's Gradle plugin dropped AGP 8 at 2.59, and Hilt
  is the DI container.

### AGP 9 only unit-tests the debug variant

`./gradlew test` still describes itself as "Run unit tests for all variants", but
AGP 9 creates a unit-test component for `debug` only. A test asserting something
about the release build therefore never runs and reports success. `app/build.gradle.kts`
turns the release component on explicitly via `androidComponents { beforeVariants … }`
— without it, `BiometricUnlockFlagTest`'s "biometrics stay on in the shipped build"
half is silently dead.

Still to come, per `../ANDROID_PORT_PLAN.md`: Retrofit + OkHttp, Room, DataStore,
WorkManager, FCM, Sentry, BiometricPrompt, Android Keystore.
